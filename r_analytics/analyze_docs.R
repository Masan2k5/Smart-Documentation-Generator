#!/usr/bin/env Rscript

# ***********************************************
# Smart Documentation Generator - R Analytics
# ***********************************************

# Load required libraries
library(jsonlite)
library(ggplot2)
library(dplyr)
library(tidyr)
library(plotly)
library(htmlwidgets)
library(knitr)

# Set paths
project_root <- file.path(dirname(getwd()))
json_path <- file.path(project_root, "build", "code_analysis.json")
stats_path <- file.path(project_root, "output", "statistics.json")
output_dir <- file.path(project_root, "r_analytics", "reports")
plots_dir <- file.path(project_root, "r_analytics", "plots")

# Create directories if they don't exist
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(plots_dir, showWarnings = FALSE, recursive = TRUE)

cat("***********************************************\n")
cat("R Analytics for Documentation Generator\n")
cat("***********************************************\n\n")

# Check if JSON files exist
if (!file.exists(json_path)) {
  stop(paste("Code analysis JSON not found at:", json_path))
}

if (!file.exists(stats_path)) {
  warning("Statistics JSON not found. Some analyses will be skipped.")
  stats_available <- FALSE
} else {
  stats_available <- TRUE
}

# ***********************************************
# 1. Load and explore data
# ***********************************************

cat("\nCode analysis data is being loaded...\n")

# Load the JSON data
code_data <- fromJSON(json_path, flatten = TRUE)

# Basic structure
cat(sprintf("Data loaded successfully for %d files\n", nrow(code_data)))

# Create a summary data frame
file_summary <- code_data %>%
  mutate(
    filename = basename(file),
    file_ext = tools::file_ext(file),
    function_count = sapply(functions, nrow),
    class_count = sapply(classes, nrow),
    total_items = function_count + class_count
  )

# Display summary
cat("\nFile Summary:\n")
print(file_summary %>% select(filename, file_ext, function_count, class_count))

# Summary statistics
cat("\nOverall Statistics:\n")
cat(sprintf("  Total files: %d\n", nrow(file_summary)))
cat(sprintf("  Total functions: %d\n", sum(file_summary$function_count)))
cat(sprintf("  Total classes: %d\n", sum(file_summary$class_count)))
cat(sprintf("  Average functions per file: %.2f\n", mean(file_summary$function_count)))
cat(sprintf("  Max functions in a file: %d\n", max(file_summary$function_count)))

# ***********************************************
# 2. Function distribution visualizations
# ***********************************************

cat("\nCreating visualizations...\n")

# Bar chart: Functions per file
p1 <- ggplot(file_summary, aes(x = reorder(filename, -function_count), 
                               y = function_count, 
                               fill = file_ext)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = function_count), vjust = -0.3, size = 3) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  labs(title = "Functions per File",
       subtitle = "Distribution of functions across source files",
       x = "File", 
       y = "Number of Functions",
       fill = "File Type") +
  scale_fill_brewer(palette = "Set3")

# Save the plot
ggsave(file.path(plots_dir, "functions_per_file.png"), p1, 
       width = 12, height = 6, dpi = 150)
cat("  Saved successfully at: functions_per_file.png\n")

# Pie chart: File type distribution
file_type_summary <- file_summary %>%
  group_by(file_ext) %>%
  summarise(count = n()) %>%
  mutate(percentage = count / sum(count) * 100)

p2 <- ggplot(file_type_summary, aes(x = "", y = count, fill = file_ext)) +
  geom_bar(stat = "identity", width = 1) +
  coord_polar("y", start = 0) +
  geom_text(aes(label = sprintf("%d (%.1f%%)", count, percentage)), 
            position = position_stack(vjust = 0.5)) +
  theme_void() +
  labs(title = "File Type Distribution",
       fill = "File Extension") +
  scale_fill_brewer(palette = "Pastel1")

ggsave(file.path(plots_dir, "file_types_pie.png"), p2, 
       width = 8, height = 6, dpi = 150)
cat("  Saved successfully at: file_types_pie.png\n")

# Histogram of function counts
p3 <- ggplot(file_summary, aes(x = function_count)) +
  geom_histogram(binwidth = 1, fill = "steelblue", color = "white", alpha = 0.7) +
  geom_density(aes(y = after_stat(count)), color = "red", size = 1) +
  theme_minimal() +
  labs(title = "Distribution of Function Counts",
       subtitle = "How many files have X functions?",
       x = "Number of Functions", 
       y = "Number of Files") +
  scale_x_continuous(breaks = 0:max(file_summary$function_count))

ggsave(file.path(plots_dir, "function_count_histogram.png"), p3, 
       width = 10, height = 5, dpi = 150)
cat("  Saved successfully at: function_count_histogram.png\n")

# ***********************************************
# 3. Documentation Coverage (if stats are available)
# ***********************************************

if (stats_available) {
  cat("\nDocumentation statistics are being loaded...\n")
  
  stats <- fromJSON(stats_path)
  
  # Create coverage dataframe
  coverage_df <- data.frame(
    Category = c("Functions", "Classes", "Files"),
    Total = c(stats$total_functions, stats$total_classes, stats$total_files),
    Documented = c(stats$functions_documented, stats$classes_documented, stats$files_with_docs),
    Coverage = c(stats$function_coverage, stats$class_coverage, 
                 stats$files_with_docs / stats$total_files * 100)
  )
  
  # Coverage bar chart
  p4 <- ggplot(coverage_df, aes(x = Category, y = Coverage, fill = Category)) +
    geom_bar(stat = "identity", width = 0.6) +
    geom_text(aes(label = sprintf("%.1f%%", Coverage)), vjust = -0.5, size = 5) +
    geom_text(aes(label = sprintf("%d/%d", Documented, Total)), 
              vjust = 1.5, color = "white", size = 4) +
    theme_minimal() +
    labs(title = "Documentation Coverage",
         subtitle = "Percentage of items with generated documentation",
         x = "", 
         y = "Coverage (%)") +
    scale_fill_brewer(palette = "Set2") +
    ylim(0, 100)
  
  ggsave(file.path(plots_dir, "coverage_chart.png"), p4, 
         width = 8, height = 6, dpi = 150)
  cat("  Saved successfully at: coverage_chart.png\n")
  
  # Print coverage summary
  cat("\nDocumentation Coverage Summary:\n")
  print(coverage_df)
  
  # Diagrams count
  if (stats$diagrams_generated > 0) {
    cat(sprintf("\nTotal diagrams generated: %d\n", stats$diagrams_generated))
    diagrams_per_file <- stats$diagrams_generated / stats$files_with_docs
    cat(sprintf("    Average diagrams per documented file: %.2f\n", diagrams_per_file))
  }
}

# ***********************************************
# 4. Interactive visualization
# ***********************************************

cat("\nInteractive visualization is being created...\n")

# Create an interactive plot of functions vs classes
p_interactive <- plot_ly(
  file_summary,
  x = ~function_count,
  y = ~class_count,
  text = ~filename,
  type = 'scatter',
  mode = 'markers',
  marker = list(
    size = ~sqrt(total_items) * 10,
    color = ~class_count,
    colorscale = 'Viridis',
    showscale = TRUE,
    opacity = 0.7
  ),
  hoverinfo = 'text',
  hovertext = ~paste(
    "File:", filename,
    "<br>Functions:", function_count,
    "<br>Classes:", class_count,
    "<br>Total items:", total_items
  )
) %>%
  layout(
    title = "Functions vs Classes by File",
    xaxis = list(title = "Number of Functions"),
    yaxis = list(title = "Number of Classes"),
    hovermode = 'closest'
  )

# Save interactive plot
saveWidget(p_interactive, file.path(output_dir, "interactive_scatter.html"), 
           selfcontained = TRUE)
cat("  Saved successfully at: interactive_scatter.html\n")

# ***********************************************
# 5. Summary
# ***********************************************

cat("\n", paste(rep("=", 40), collapse = ""), "\n")
cat("R analysis completed successfully\n")
cat(paste(rep("=", 40), collapse = ""), "\n")
cat(sprintf("\n📁 Plots saved to: %s\n", plots_dir))
cat(sprintf("📁 Reports saved to: %s\n", output_dir))
cat("\nTo generate the HTML report, run:\n")
cat("  Rscript render_report.R\n")