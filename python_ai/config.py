"""
Configuration settings for the Smart Documentation Generator.
"""
#Imports Phyton's object-oriented path handling library
#that provides cross-platform path manipulation.
from pathlib import Path

#OLLAMA_URL: endpoint where the local Ollama server is running.
#MODEL: specifies the LLM model to use.
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "codellama:7b"

#TEMPERATURE: controls the randomness of the LLM's output (0.0 = deterministic, higher = more random).
#MAX_TOKENS: maximum number of tokens in the LLM's response.
#MAX_RETRIES: number of times to retry a request if it fails.
TEMPERATURE = 0.3
MAX_TOKENS = 1500
MAX_RETRIES = 5

#PARALLEL_WORKERS: number of worker threads for parallel processing.
#CACHE_ENABLED: whether to enable caching of LLM responses to speed up repeated requests.
PARALLEL_WORKERS = 3
CACHE_ENABLED = True

#PROJECT_ROOT: the root directory of the project, calculated relative to this config file.
#JSON_PATH: path to the input JSON file containing code analysis results.
#OUTPUT_DIR: directory where the generated markdown documentation will be saved.
PROJECT_ROOT = Path(__file__).parent.parent
JSON_PATH = PROJECT_ROOT / "build" / "code_analysis.json"
OUTPUT_DIR = PROJECT_ROOT / "output" / "markdown"

#Boolean flag to enable or disable debug mode, which 
#can provide more verbose output for troubleshooting.
DEBUG = False