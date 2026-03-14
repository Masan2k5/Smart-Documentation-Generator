#include <iostream>
#include <filesystem>
#include <vector>
#include <string>
#include <fstream>
#include <sstream>
#include "json.hpp"
#include <regex>

namespace fs = std::filesystem;
using json = nlohmann::json;

struct FunctionInfo {
    std::string name; //Name of the function
    std::string return_type; //Return type of the function
    std::vector<std::string> parameters; //List of parameters (type and name)
    size_t line_number; //Line number where the function is defined
    std::string signature; //Full function signature (for better context in JSON output)
};

struct ClassInfo {
    std::string name; //Name of the class
    size_t line_number; //Line number where the class is defined
};

struct FileInfo {
    fs::path file_path; //Path to the source file
    std::vector<std::string> lines; //All lines of the file (used for analysis and JSON output)
    size_t line_count; //Total number of lines in the file
    std::vector<FunctionInfo> functions; //List of functions found in the file
    std::vector<ClassInfo> classes; //List of classes found in the file
};

class CodeAnalyzer {
    public:
    /*Uses regex to extract function definitions from the file lines. 
    It captures the return type, function name, parameters, and line number.
    Pattern matches: return_type function_name(parameters) { ... } */
    std::vector<FunctionInfo> extract_functions(const FileInfo& file) {
        std::vector<FunctionInfo> functions;
        std::regex func_pattern{R"(([\w:]+)\s+(\w+)\s*\(([^)]*)\)\s*(?:const)?\s*(?:override)?\s*\{?)"};

        for (size_t i = 0; i < file.lines.size(); i++) {
            std::smatch matches;
            if (std::regex_search(file.lines[i], matches, func_pattern)) {
                if (matches.size() >= 3) {
                    FunctionInfo func;
                    func.return_type = matches[1];
                    func.name = matches[2];
                    func.parameters = split_parameters(matches[3]);
                    func.line_number = i + 1;
                    func.signature = file.lines[i];
                    functions.push_back(func);
                }
            }
        }

        return functions;
    }

    std::vector<ClassInfo> extract_classes(const FileInfo& file) {
        //Uses regex to extract class definitions from the file lines.
        //It captures the class name and line number.
        //Pattern matches: class ClassName { ... } or class ClassName : public BaseClass { ... }
        std::vector<ClassInfo> classes;
        std::regex class_pattern{R"(class\s+(\w+)\s*(?:\:\s*(?:public|private|protected)\s+(\w+))?\s*\{)"};

        for (size_t i = 0; i < file.lines.size(); i++) {
            std::smatch matches;
            if (std::regex_search(file.lines[i], matches, class_pattern)) {
                ClassInfo cls;
                cls.name = matches[1];
                cls.line_number = i + 1;
                classes.push_back(cls);
            }
        }
        return classes;
    }

    private:
    //Helper function to split parameter string into individual parameters, trimming whitespace.
    std::vector<std::string> split_parameters(const std::string& param_str) {
        std::vector<std::string> params;
        if (param_str.empty() || param_str == "void") {
            return params;
        }
        std::stringstream ss(param_str);
        std::string param;
        while (std::getline(ss, param, ',')) {
            param.erase(0, param.find_first_not_of(" \t"));
            param.erase(param.find_last_not_of(" \t") + 1);
            params.push_back(param);
        }
        return params;
    }

};

//The following three functions overload the to_json function for the FunctionInfo, ClassInfo, and FileInfo structs.
void to_json(json& j, const FunctionInfo& f) {
    j = json{
        {"name", f.name},
        {"return_type", f.return_type},
        {"parameters", f.parameters},
        {"line_number", f.line_number},
        {"signature", f.signature}
    };
};

void to_json(json& j, const ClassInfo& c) {
    j = json{
        {"name", c.name},
        {"line_number", c.line_number}
    };
};

void to_json(json& j, const FileInfo& f) {
    j = json{
        {"file", f.file_path.string()},
        {"line_count", f.line_count},
        {"functions", f.functions},
        {"classes", f.classes}
    };
};
/*Reads the content of a file and returns a FileInfo struct containing the file path, lines, line count, and placeholders for functions and classes.
*/
FileInfo read_file(const fs::path& file_path) {
    FileInfo info;
    info.file_path = file_path;
    
    std::ifstream file(file_path.string());
    if (!file.is_open()) {
        throw std::runtime_error("Cannot open file: " + file_path.string());
    }
    
    std::string line;
    while (std::getline(file, line)) {
        info.lines.push_back(line);
    }
    info.line_count = info.lines.size();
    file.close();
    return info;
}

/*This function recursively scans the given directory for C++ source files and returns a list of their paths. 
It checks for common C++ file extensions and handles filesystem errors gracefully.
*/
std::vector<fs::path> find_source_files(const fs::path& root_dir) {
    std::vector<fs::path> source_files;
    
    try {
        for (const auto& entry : fs::recursive_directory_iterator(root_dir)) {
            if (fs::is_regular_file(entry)) {
                fs::path file_path = entry.path();
                std::string ext = file_path.extension().string();
                if (ext == ".cpp" || ext == ".c" || ext == ".h" || 
                    ext == ".hpp" || ext == ".cc" || ext == ".cxx") {
                    source_files.push_back(file_path);
                    std::cout << "Found: " << file_path << std::endl;
                }
            }
        }
    } catch (const fs::filesystem_error& e) {
        std::cerr << "Filesystem error: " << e.what() << std::endl;
    }
    
    return source_files;
}

int main(int argc, char* argv[]) {
    /*Validates command-line arguments to ensure a directory path is provided. 
    It checks if the path exists and is a directory, then proceeds to scan for 
    source files and analyze them. */
    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " <directory_path>" << std::endl;
        return 1;
    }
    
    fs::path root_dir = argv[1];
    
    if (!fs::exists(root_dir) || !fs::is_directory(root_dir)) {
        std::cerr << "Error: " << root_dir << " is not a valid directory." << std::endl;
        return 1;
    }
    /* Finds all C++ source files in the specified directory and its subdirectories. 
    It uses the find_source_files function to get a list of file paths, which are then analyzed for functions and classes.
    */
    std::cout << "Scanning directory: " << root_dir << std::endl;
    auto files = find_source_files(root_dir);
    std::cout << "\nFound " << files.size() << " source files." << std::endl;
    
    std::vector<FileInfo> all_files_info;
    CodeAnalyzer analyzer;

    /* Prints the name of each file being analyzed and the results of the analysis, 
    including the number of lines, functions, and classes found.
    */
    for(const auto& file_path : files) {
        std::cout <<"Analyzing: "<<file_path.filename() << "... ";
        try {
            FileInfo info = read_file(file_path);

            info.functions = analyzer.extract_functions(info);
            info.classes = analyzer.extract_classes(info);

            all_files_info.push_back(info);

            std::cout << "done (" << info.line_count << " lines, " 
                      << info.functions.size() << " functions, " 
                      << info.classes.size() << " classes)" << std::endl;
        } catch (const std::exception & e) {
            std::cerr << "ERROR: " << e.what() << std::endl;
        }
    }

    size_t total_functions = 0, total_classes = 0;
    for (const auto& info : all_files_info) {
        total_functions += info.functions.size();
        total_classes += info.classes.size();
    }

    /* Prints a summary of the analysis, including the total number of functions 
    and classes found across all analyzed files.
    */
    std::cout << "\nSummary: " << total_functions << " functions, " 
                << total_classes << " classes across " 
                << all_files_info.size() << " files." << std::endl;

    json output = json::array();
    for(const auto& info : all_files_info) {
        output.push_back(info);
    }
    /*Writes the analysis results to a JSON file named code_analysis.json.
    */
    std::ofstream out_file("code_analysis.json");
    if (out_file.is_open()) {
        out_file << output.dump(2);
        out_file.close();
        std::cout << "\nAnalysis is written to code_analysis.json" << std::endl;
    } else {
        std::cerr << "Failed to write the output file!" << std::endl;
    }

    return 0;
}