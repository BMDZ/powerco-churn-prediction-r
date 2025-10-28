#!/usr/bin/env Rscript
# 04_Model_Interpretation.R - PowerCo Customer Churn Prediction
# Model Interpretation using SHAP
# =================================================

library(tidyverse)
library(tidymodels)
library(fastshap)
library(vip)

# 1. Load processed data and split ---------------------------------------
df_full <- read_csv("data/processed/features_selected.csv")
df_full$churn <- as.factor(df_full$churn)

set.seed(42)
split <- initial_split(df_full, prop = 0.8, strata = churn)
train <- training(split)
test <- testing(split)

# 2. Load best model ------------------------------------------------------
best_model_file <- "models/xgb.rds"
model <- readRDS(best_model_file)

# Extract fitted model object
fitted_model <- extract_fit_parsnip(model)$fit

# 3. Prepare test features for SHAP --------------------------------------
test_features <- test %>%
  select(-id, -churn) %>%
  select(where(is.numeric))

# For fastshap speed, optionally sample:
# set.seed(42)
# test_sample <- test_features %>% slice_sample(n = 500)
test_sample <- test_features

# 4. Define prediction wrapper for fastshap ------------------------------
pred_wrapper <- function(object, newdata) {
  new_data <- as.data.frame(newdata)
  if (inherits(object, "xgb.Booster")) {
    pred <- predict(object, as.matrix(new_data))
  } else if (inherits(object, "ranger")) {
    pred <- predict(object, data = new_data)$predictions[, 2]
  } else {
    pred <- predict(object, new_data = new_data, type = "response")
  }
  return(as.numeric(pred))
}

# 5. Calculate SHAP values ------------------------------------------------
shap_values <- fastshap::explain(
  object = fitted_model,
  X = test_sample,
  pred_wrapper = pred_wrapper,
  nsim = 50,
  adjust = TRUE
)

# 6. Feature importance data frame ----------------------------------------
mean_abs_shap <- colMeans(abs(shap_values), na.rm = TRUE)

importance_df <- tibble(
  feature = names(mean_abs_shap),
  importance = mean_abs_shap
) %>%
  arrange(desc(importance))

# Save importance CSV
write_csv(importance_df, "reports/shap_importance.csv")
cat("✓ SHAP importance saved to reports/shap_importance.csv\n")

# 7. Plot SHAP importance bar chart ---------------------------------------
dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)

p1 <- importance_df %>% 
  slice(1:20) %>%
  ggplot(aes(x = reorder(feature, importance), y = importance)) +
  geom_col(fill = "#3498db", alpha = 0.8) +
  coord_flip() +
  labs(
    title = "SHAP Feature Importance",
    subtitle = "Top 20 Features by Mean |SHAP|",
    x = "Feature",
    y = "Mean |SHAP Value|"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5)
  )

ggsave("reports/figures/shap_importance.png", p1, width = 10, height = 8, dpi = 300)
cat("✓ SHAP importance plot saved\n")

# 8. SHAP Summary beeswarm plot -------------------------------------------
shap_long <- shap_values %>%
  as_tibble() %>%
  mutate(obs = row_number()) %>%
  pivot_longer(-obs, names_to = "feature", values_to = "shap_value") %>%
  left_join(
    test_sample %>% 
      mutate(obs = row_number()) %>%
      pivot_longer(-obs, names_to = "feature", values_to = "feature_value"),
    by = c("obs", "feature")
  ) %>%
  filter(feature %in% importance_df$feature[1:15])

p2 <- ggplot(shap_long, aes(x = shap_value, y = reorder(feature, shap_value, FUN = function(x) mean(abs(x))))) +
  geom_point(aes(color = feature_value), alpha = 0.5, size = 1.5) +
  scale_color_gradient(low = "blue", high = "red", name = "Feature\nValue") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  labs(
    title = "SHAP Summary Plot",
    subtitle = "Impact of Features on Churn Prediction",
    x = "SHAP Value (Impact on Model Output)",
    y = "Feature"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5)
  )

ggsave("reports/figures/shap_summary.png", p2, width = 10, height = 8, dpi = 300)
cat("✓ SHAP summary plot saved\n")

# 9. Dependence plots for the top 5 features ------------------------------
cat("Creating dependence plots for top 5 features...\n")

for (i in 1:min(5, nrow(importance_df))) {
  feature_name <- importance_df$feature[i]
  plot_data <- tibble(
    feature_value = test_sample[[feature_name]],
    shap_value = shap_values[, feature_name]
  )
  
  p <- ggplot(plot_data, aes(x = feature_value, y = shap_value)) +
    geom_point(alpha = 0.5, color = "#3498db") +
    geom_smooth(method = "loess", se = TRUE, color = "#e74c3c") +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    labs(
      title = paste("SHAP Dependence Plot:", feature_name),
      x = feature_name,
      y = "SHAP Value"
    ) +
    theme_minimal(base_size = 11) +
    theme(plot.title = element_text(face = "bold", hjust = 0.5))
  
  filename <- paste0("reports/figures/shap_dependence_", gsub("[^[:alnum:]]", "_", feature_name), ".png")
  ggsave(filename, p, width = 8, height = 6, dpi = 300)
  cat("  ✓", feature_name, "\n")
}

cat("\n✓ Model interpretation complete!\n")
