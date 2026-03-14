import json
import os
import requests #Communication with Ollama LLM API
import re
import time
import random
import multiprocessing
from tqdm import tqdm
from contextlib import contextmanager
from pathlib import Path
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed #Enables parallel processing of files
from prompts import function_prompt, class_prompt, system_prompt
from config import (
    OLLAMA_URL, MODEL, TEMPERATURE, MAX_TOKENS, MAX_RETRIES,
    PARALLEL_WORKERS, CACHE_ENABLED, JSON_PATH, OUTPUT_DIR, DEBUG
)
#Custom modules such as prompts, config seperate the 
# configuration and prompt templates from the main logic, 
# making it easier to manage and update them without modifying the core code.

#Conditional logging that only outputs when DEBUG is enabled.
#Helps troubleshoot issues without cluttering the output during normal runs.
#Includes visual cues for easy scanning.
def debug_log(message, data=None):
    """Log debug information if DEBUG is enabled."""
    if DEBUG:
        print(f"\n🔍 DEBUG: {message}")
        if data:
            print(data)
            print("-" * 40)

#Uses context manager patterns to measure code blocks' execution time.
#Can be used with with timer("operation name") to automatically track duration.
#Useful for performance monitoring and identifying bottlenecks in the documentation generation process.
@contextmanager
def timer(name):
    """Context manager to time operations."""
    start = time.time()
    yield
    elapsed = time.time() - start
    print(f"  ⏱️  {name} took {elapsed:.2f} seconds")

#Delay time doubles after each failure (2s, 4s, 8s, etc.)
#Wait time is randomized to avoid thundering herd problem when many requests fail simultaneously.
#Catches specific exceptions like connection errors, timeouts, and HTTP errors to determine if a retry is warranted.
#Special handling for 429 (Too Many Requests) status code.
#Returns error messages instead of crashing after max retries are exceeded, allowing the process to continue with other files.
def ask_llama_with_retry(prompt, system=None, max_retries=MAX_RETRIES):
    """
    Call LLM with exponential backoff and full jitter retry logic.
    Waits longer between each failed attempt to avoid overwhelming the API.
    """
    base_delay = 1
    max_delay = 60
    
    for attempt in range(max_retries):
        try:
            payload = {
                "model": MODEL,
                "prompt": prompt,
                "system": system,
                "stream": False,
                "options": {
                    "temperature": TEMPERATURE,
                    "max_tokens": MAX_TOKENS
                }
            }
            
            print(f"  Sending request to LLM (attempt {attempt + 1}/{max_retries})...")
            response = requests.post(OLLAMA_URL, json=payload)
            response.raise_for_status()
            
            debug_log("LLM Response", response.json()["response"][:200] + "...")
            
            return response.json()["response"]
            
        except requests.exceptions.ConnectionError as e:
            print(f"  Connection error: {e}")
            if attempt == max_retries - 1:
                return "[Error: Connection failed after retries]"
                
        except requests.exceptions.Timeout as e:
            print(f"  Timeout error: {e}")
            if attempt == max_retries - 1:
                return "[Error: Timeout after retries]"
                
        except requests.exceptions.HTTPError as e:
            if response.status_code == 429:
                print(f"  Rate limited (429). Retrying...")
            elif response.status_code >= 500:
                print(f"  Server error {response.status_code}. Retrying...")
            else:
                print(f"  HTTP error {response.status_code}: {e}")
                return f"[Error: HTTP {response.status_code}]"
                
        except Exception as e:
            print(f"  Unexpected error: {e}")
            if attempt == max_retries - 1:
                return "[Error: Unexpected error after retries]"
        
        delay = min(max_delay, base_delay * (2 ** attempt))
        jitter = random.uniform(0, delay)
        print(f"  Retrying in {jitter:.1f} seconds...")
        time.sleep(jitter)
    
    return "[Error: Max retries exceeded]"

#Uses regex to specify mermaid diagram code blocks in the LLM response.
#re.DOTALL allows the pattern to match across multiple lines, which is necessary for code blocks.
#Returns only diagram code without the surrounding markdown formatting, making it easier to save and use for rendering diagrams.
def extract_mermaid(text):
    """Extract Mermaid diagram code if present."""
    pattern = r"```mermaid\n(.*?)\n```"
    match = re.search(pattern, text, re.DOTALL)
    return match.group(1) if match else None

#Saves extracted Mermaid code to .mmd files.
#These can be rendered by Mermaid viewers or integrated into documentaton.
#Returns a boolean that indicates success or failure.
def save_mermaid_diagram(mermaid_code, output_path):
    """Save Mermaid code to a .mmd file."""
    if mermaid_code:
        with open(output_path, "w") as f:
            f.write(mermaid_code)
        return True
    return False

#Validates that input JSON has all expected fields.
#Prevents runtime errors from missing data.
#Returns list of issue rather than throwing exceptions.
def validate_json_structure(code_data):
    """Validate that the loaded JSON has the expected structure."""
    required_file_fields = ['file', 'functions', 'classes']
    required_function_fields = ['name', 'return_type', 'parameters', 'line_number', 'signature']
    required_class_fields = ['name', 'line_number']
    
    issues = []
    
    for idx, file_info in enumerate(code_data):
        for field in required_file_fields:
            if field not in file_info:
                issues.append(f"File {idx} missing field: {field}")
        
        for func_idx, func in enumerate(file_info.get('functions', [])):
            for field in required_function_fields:
                if field not in func:
                    issues.append(f"File {idx}, function {func_idx} missing field: {field}")
        
        for cls_idx, cls in enumerate(file_info.get('classes', [])):
            for field in required_class_fields:
                if field not in cls:
                    issues.append(f"File {idx}, class {cls_idx} missing field: {field}")
    
    return issues

#Skips files that already have their documentation generated (if enabled).
#Parses parameter strings into type/name pairs for better display in documentation.
#Formats prompts with data specific to files.
#Saves any generated Mermaid diagram.
#Builds structured markdown documentation with headers and separators.
def process_single_file(file_info, output_dir):
    """Process a single file and return its markdown content and metadata."""
    file_path = file_info['file']
    base_name = Path(file_path).stem
    out_file = output_dir / f"{base_name}.md"
    
    if out_file.exists() and CACHE_ENABLED:
        return f"Skipped {base_name}.md (already exists)"
    
    md_content = f"# Documentation for {file_path}\n\n"
    
    functions = file_info.get('functions', [])
    for func in functions:
        params_list = func['parameters']
        if params_list and params_list != [""]:
            formatted_params = ""
            for param in params_list:
                parts = param.strip().split()
                if len(parts) >= 2:
                    param_type = " ".join(parts[:-1])
                    param_name = parts[-1]
                    formatted_params += f"- `{param_type} {param_name}`\n"
                else:
                    formatted_params += f"- `{param}`\n"
        else:
            formatted_params = "None"
        
        prompt = function_prompt.format(
            file=file_path,
            name=func['name'],
            return_type=func['return_type'],
            parameters=", ".join(func['parameters']),
            parameters_formatted=formatted_params,
            signature=func['signature']
        )
        
        doc = ask_llama_with_retry(prompt, system=system_prompt)
        
        mermaid_code = extract_mermaid(doc)
        if mermaid_code:
            diagram_path = output_dir / f"{base_name}_{func['name']}_diagram.mmd"
            save_mermaid_diagram(mermaid_code, diagram_path)
        
        md_content += f"## Function: {func['name']}\n\n{doc}\n\n---\n\n"
    
    classes = file_info.get('classes', [])
    for cls in classes:
        prompt = class_prompt.format(
            file=file_path,
            name=cls['name']
        )
        doc = ask_llama_with_retry(prompt, system=system_prompt)
        
        mermaid_code = extract_mermaid(doc)
        if mermaid_code:
            diagram_path = output_dir / f"{base_name}_{cls['name']}_class_diagram.mmd"
            save_mermaid_diagram(mermaid_code, diagram_path)
        
        md_content += f"## Class: {cls['name']}\n\n{doc}\n\n---\n\n"
    
    with open(out_file, "w") as f:
        f.write(md_content)
    
    return f"Completed {base_name}.md ({len(functions)} functions, {len(classes)} classes)"

#Calculates metrics about the documentation proccess.
#Tracks function and classes' coverage percentages.
#Uses Path.glob() to find generated diagram files.
#Helps quantify documentation completeness.
def generate_statistics(code_data, output_dir):
    """Generate detailed statistics about the documentation."""
    stats = {
        "total_files": len(code_data),
        "total_functions": 0,
        "total_classes": 0,
        "files_with_docs": 0,
        "functions_documented": 0,
        "classes_documented": 0,
        "diagrams_generated": 0,
        "files_by_type": {}
    }
    
    for file_info in code_data:
        file_ext = Path(file_info['file']).suffix
        stats['files_by_type'][file_ext] = stats['files_by_type'].get(file_ext, 0) + 1
        
        func_count = len(file_info.get('functions', []))
        class_count = len(file_info.get('classes', []))
        
        stats['total_functions'] += func_count
        stats['total_classes'] += class_count
        
        base_name = Path(file_info['file']).stem
        md_file = output_dir / f"{base_name}.md"
        if md_file.exists():
            stats['files_with_docs'] += 1
            stats['functions_documented'] += func_count
            stats['classes_documented'] += class_count
            
            diagrams = list(output_dir.glob(f"{base_name}_*.mmd"))
            stats['diagrams_generated'] += len(diagrams)
    
    stats['function_coverage'] = (
        stats['functions_documented'] / stats['total_functions'] * 100 
        if stats['total_functions'] > 0 else 0
    )
    stats['class_coverage'] = (
        stats['classes_documented'] / stats['total_classes'] * 100 
        if stats['total_classes'] > 0 else 0
    )
    
    return stats

#1. Setup & Validation: 
#Creates output directory if it doesn't exist.
#Validates input JSON file if it exists and has a correct structure.
#Warns the user about issues found but procceeds (fault-tolerant design).

#2. Parallel Processing:
#Uses ThreadPoolExecutor to process multiple files concurrently.
#Calculates optimal number of workers based on CPU cores and a predefined limit.
#Tracks progress with tqdm and provides ETA based on average processing time.

#3. Index Generation:
#Creates an index page linking all documentation and alphabetically sorts files for easy navigation.

#4. Statistics & Reporting:
#Generates comprehensive statistics about the documentation process, including coverage percentages and file type breakdowns.
#Saves statistics to a JSON file for further analysis or reporting.
#Displays summary readable by humans in the console.
def main():
    """Main execution function."""
    global start_time, processed_items, total_items
    
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    print(f"Looking for JSON at: {JSON_PATH}")
    print(f"File exists: {JSON_PATH.exists()}")
    
    if not JSON_PATH.exists():
        print(f"❌ Error: JSON file not found at {JSON_PATH}")
        print("Please run the C++ parser first to generate code_analysis.json")
        return
    
    with open(JSON_PATH, "r") as f:
        code_data = json.load(f)
    
    validation_issues = validate_json_structure(code_data)
    if validation_issues:
        print("\n⚠️  WARNING: JSON validation found issues:")
        for issue in validation_issues[:10]:
            print(f"  - {issue}")
        if len(validation_issues) > 10:
            print(f"  ... and {len(validation_issues) - 10} more issues")
        print("Continuing anyway, but documentation may be incomplete.\n")
    else:
        print("✅ JSON validation passed.\n")    
    
    print(f"Loaded {len(code_data)} files from analysis.")
    for file_info in code_data:
        print(f"  {file_info['file']}: {len(file_info['functions'])} functions, {len(file_info['classes'])} classes")
    
    start_time = datetime.now()
    total_items = sum(len(f.get('functions', [])) + len(f.get('classes', [])) for f in code_data)
    processed_items = 0
    
    print(f"\n📊 Need to document {total_items} items (functions + classes) across {len(code_data)} files")
    
    max_workers = min(multiprocessing.cpu_count(), PARALLEL_WORKERS)
    print(f"⚡ Processing with {max_workers} parallel workers...")
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(process_single_file, file_info, OUTPUT_DIR) 
                   for file_info in code_data]
        
        for future in tqdm(as_completed(futures), total=len(futures), 
                           desc="Processing files", unit="file"):
            try:
                result = future.result(timeout=300)
                if DEBUG:
                    print(f"\n{result}")
                
                processed_items += 1
                if processed_items % 5 == 0:
                    elapsed = (datetime.now() - start_time).total_seconds()
                    avg_time = elapsed / processed_items if processed_items > 0 else 0
                    remaining = total_items - processed_items
                    eta = str(timedelta(seconds=int(avg_time * remaining))) if remaining > 0 else "0:00:00"
                    print(f"\n  ⏱️  Progress: {processed_items}/{total_items} items, ETA: {eta}")
                    
            except Exception as e:
                print(f"\n❌ Error processing file: {e}")
    
    print("\nCreating index page...")
    unique_files = set()
    for file_info in code_data:
        base_name = Path(file_info['file']).stem
        unique_files.add(base_name)
    
    index_content = "# Smart Documentation Generator Output\n\n"
    for base_name in sorted(unique_files):
        index_content += f"- [{base_name}]({base_name}.md)\n"
    
    with open(OUTPUT_DIR / "index.md", "w") as f:
        f.write(index_content)
    print(f"Saved {OUTPUT_DIR / 'index.md'}")
    
    stats = generate_statistics(code_data, OUTPUT_DIR)
    
    print("\n" + "="*60)
    print("📊 DOCUMENTATION STATISTICS")
    print("="*60)
    print(f"Files: {stats['total_files']} total, {stats['files_with_docs']} documented ({stats['files_with_docs']/stats['total_files']*100:.1f}%)")
    print(f"Functions: {stats['total_functions']} total, {stats['functions_documented']} documented ({stats['function_coverage']:.1f}%)")
    print(f"Classes: {stats['total_classes']} total, {stats['classes_documented']} documented ({stats['class_coverage']:.1f}%)")
    print(f"Diagrams generated: {stats['diagrams_generated']}")
    print("\nFile types:")
    for ext, count in stats['files_by_type'].items():
        print(f"  {ext}: {count}")
    print("="*60)

    stats_path = OUTPUT_DIR.parent / "statistics.json"
    with open(stats_path, "w") as f:
        json.dump(stats, f, indent=2)
    print(f"\n📈 Statistics saved to: {stats_path}")
    
    total_time = datetime.now() - start_time
    print(f"\n⏱️  Total processing time: {total_time}")
    print("\n✅ Documentation generation complete!")

#A standard Python idiom that ensures the main() function is only executed 
# when the script is run directly, not when imported as a module.
if __name__ == "__main__":
    main()