#!/usr/bin/env Rscript
# PowerCo SME Churn Prediction Pipeline in R
# Uses:
#  - ml_case_training_data.csv
#  - ml_case_training_hist_data.csv
#  - ml_case_training_output.csv
# Generates:
#  - EDA plots, feature engineering, 4 models, SHAP, ROI analysis.
```{r}
setwd("C:/Users/baouc/OneDrive - Bournemouth University/Master/Performance Mgt/R/Case studies")
```
# PowerCo Customer Churn Prediction – Exploratory Data Analysis
# ======================================================================
```{r}
library(tidyverse)
library(skimr)
library(yardstick)
library(corrplot)
library(VIM)
library(gridExtra)
````
```{r}
# 1. Load data
train <- read_csv("ml_case_training_data.csv")
hist  <- read_csv("ml_case_training_hist_data.csv")
out   <- read_csv("ml_case_training_output.csv")
df <- train %>% left_join(out, by="id") %>% left_join(hist, by="id")

````
```{r}
# 2. Missing values
mv <- df %>% summarise(across(everything(), ~sum(is.na(.)))) %>%
  pivot_longer(everything(), names_to="var", values_to="missing") %>%
  filter(missing>0)
print(mv)
if(nrow(mv)){
  aggr_plot <- aggr(df, prop=FALSE, numbers=TRUE)
  png("reports/figures/missing_data.png",width=800,height=600)
  plot(aggr_plot); dev.off()
}
````
```{r}
# 4. Numerical distributions
nums <- c("cons_12m","cons_last_month","net_margin","forecast_discount_energy")
for(col in nums){
  if(col %in% names(df)){
    p <- ggplot(df,aes_string(x=col,fill="factor(churn)"))+
      geom_density(alpha=0.5)+ theme_minimal()+
      scale_fill_manual(values=c("#2ecc71","#e74c3c"))+
      labs(title=paste("Dist of",col))
    ggsave(paste0("reports/figures/dist_",col,".png"),p,width=6,height=4)
  }
}
````
```{r}
# 5. Correlation matrix
corr_cols <- intersect(c(nums,"churn"), names(df))
cm <- df %>% select(all_of(corr_cols)) %>% cor(use="complete.obs")
png("reports/figures/corr.png",800,800); corrplot(cm, method="color"); dev.off()

````
```{r}
# 6. T-tests
for(col in nums){
  if(col %in% names(df)){
    g0 <- df %>% filter(churn==0) %>% pull(col)
    g1 <- df %>% filter(churn==1) %>% pull(col)
    if(length(g0)>10 & length(g1)>10){
      t <- t.test(g0,g1)
      cat(col,": p=",round(t$p.value,4),"\n")
    }
  }
}
````
```{r}
library(tidyverse)
library(lubridate)
# 2. Dates
date_cols <- c("date_activ","date_end","date_first_activ","date_modif_prod","date_renewal","price_date")
df[date_cols] <- map(df[date_cols], ~as_date(.x, format="%Y-%m-%d"))
ref <- ymd("2016-01-31")
```
```{r}
# 3. Temporal
df <- df %>% mutate(
  days_to_renew = as.numeric(date_renewal - ref),
  tenure_days   = as.numeric(ref - date_activ),
  contract_len  = as.numeric(date_end - date_activ),
  days_mod      = as.numeric(ref - date_modif_prod)
)
````
```{r}
# 4. Consumption
df <- df %>% mutate(
  avg_mon_cons = cons_12m/12,
  cons_trend   = cons_last_month/(avg_mon_cons+1),
  cons_pct     = (cons_last_month-avg_mon_cons)/(avg_mon_cons+1)*100,
  total_cons   = cons_12m+cons_gas_12m
)
```
```{r}
# 5. Economic
df <- df %>% mutate(
  margin_pc   = net_margin/(cons_12m+1),
  est_rev     = cons_12m*price_p1_fix,
  disc_rate   = forecast_discount_energy/(est_rev+1)
)
````
```{r}
# 6. Categorical encode
# Install fastDummies if not already installed
if (!requireNamespace("fastDummies", quietly = TRUE)) {
  install.packages("fastDummies")
}

library(fastDummies)

df <- df %>% mutate(
  activity_new = fct_lump(activity_new, n = 10),
  channel_sales = fct_lump(channel_sales, n = 10)
) %>% 
  fastDummies::dummy_cols(select_columns = c("activity_new", "channel_sales", "origin_up"), remove_first_dummy = TRUE)
````
```{r}
# 7. Impute missing
num_cols <- df %>% select(where(is.numeric)) %>% names()
df[num_cols] <- df[num_cols] %>% map_dfc(~replace_na(.x,median(.x,na.rm=TRUE)))
````
```{r}
# 8. Feature selection (numeric-only)
# ============================================================================

# Ensure the output directory exists
if (!dir.exists("data/processed")) dir.create("data/processed", recursive = TRUE)

# 8. Feature selection (numeric-only)
num_cols <- df %>% select(-id, -churn) %>% select(where(is.numeric)) %>% names()
corr_mat <- df %>% select(all_of(num_cols), churn) %>% cor(use="complete.obs")
ord <- sort(abs(corr_mat[,"churn"]), decreasing = TRUE)
selected <- names(ord)[2:26]

# Now safe to write
df %>%
  select(id, churn, all_of(selected)) %>%
  write_csv("data/processed/features_selected.csv")

cat("Selected features:\n", paste(selected, collapse = ", "), "\n")


````
# 03 Modeling
```{r}
library(tidyverse)
library(tidymodels)
library(themis)
library(magrittr)

````
```{r}
# 1. Load and sample
df_full <- readr::read_csv("data/processed/features_selected.csv")


# Ensure churn is factor
df_full$churn <- as.factor(df_full$churn)  


# 2. Split
split <- initial_split(df_full, prop = .8, strata = churn)

train <- training(split); test <- testing(split)

# 3. Recipe (drop id, handle novel levels)
rec <- recipe(churn ~ ., data = train) %>%
  update_role(id, new_role = "ID") %>%
  step_novel(all_nominal_predictors()) %>%             
  step_dummy(all_nominal_predictors(), one_hot = FALSE) %>%
  step_zv(all_predictors()) %>%                        
  step_impute_median(all_numeric_predictors()) %>%
  step_normalize(all_numeric_predictors())

rec

# 4. Specs with minimal trees (for quick test)
specs <- list(
  lr  = logistic_reg() %>% set_engine("glm"),
  rf  = rand_forest(trees = 200, min_n = 10) %>% 
    set_engine("ranger", num.threads = 4) %>% 
    set_mode("classification"),
  xgb = boost_tree(trees = 200, tree_depth = 6, learn_rate = 0.05) %>% 
    set_engine("xgboost", nthread = 4) %>% 
    set_mode("classification")
)
specs





# 5. Fit models
fits <- purrr::imap(
  specs,
  ~ workflow() %>% add_model(.x) %>% add_recipe(rec) %>% fit(data = train)
)

# 6. Evaluate
yte <- test$churn
res <- purrr::map_df(fits, function(wf) {
  pr <- predict(wf, test, type = "prob") %>% pull(.pred_1)
  prc <- ifelse(pr >= 0.35, 1, 0)
  prc <- factor(prc, levels = levels(yte))
  tibble(
    roc  = roc_auc_vec(yte, pr),
    acc  = accuracy_vec(yte, prc),
    prec = precision_vec(yte, prc),
    rec  = recall_vec(yte, prc),
    f1   = f_meas_vec(yte, prc)
  )
}, .id = "model")

print(res)

```
```{r}
# 7. Save models
dir.create("models", showWarnings = FALSE)
walk2(fits, names(fits), ~saveRDS(.x, file.path("models", paste0(.y, ".rds"))))

cat("\n✓ Models saved to models/\n")

```

```{r}
library(tidyverse)
library(tidymodels)
library(fastshap)
library(vip)
```
# 1. LOAD DATA AND MODEL
```{r}
df_full <- read_csv("data/processed/features_selected.csv", show_col_types = FALSE)
df_full$churn <- as.factor(df_full$churn)
````
```{r}
# Re-create the same split as in 03_Modeling.R
set.seed(42)
split <- initial_split(df_full, prop = 0.8, strata = churn)
train <- training(split)
test <- testing(split)
```
```{r}
# Load best model (adjust filename to your best model: lr.rds, rf.rds, xgb.rds, etc.)
best_model_file <- "models/xgb.rds"  # Change to your best model
model <- readRDS(best_model_file)
```
#2. EXTRACT FITTED MODEL FROM WORKFLOW
# Extract the actual fitted model object from the workflow
```{r}

fitted_model <- extract_fit_parsnip(model)$fit

```
# 3. PREPARE DATA FOR SHAP (WITHOUT ID COLUMN)
```{r}
# Remove id and churn columns for SHAP calculation
test_features <- test %>% 
  select(-id, -churn) %>%
  select(where(is.numeric))  # Keep only numeric features
```
```{r}
# Sample for faster computation (optional)
set.seed(42)
n_sample <- min(500, nrow(test_features))
test_sample <- test_features
# 4. DEFINE PREDICTION WRAPPER```
```{r}
# Prediction function for SHAP (returns probabilities for class 1)
pred_wrapper <- function(object, newdata) {
  # Convert to data frame if matrix
  if (is.matrix(newdata)) {
    newdata <- as.data.frame(newdata)
  }
  # Get predictions (adjust for your model type)
  if (inherits(object, "xgb.Booster")) {
    # XGBoost
    pred <- predict(object, as.matrix(newdata))
  } else if (inherits(object, "ranger")) {
    # Random Forest (ranger)
    pred <- predict(object, data = newdata)$predictions[, 2]
  } else {
    # Generic
    pred <- predict(object, newdata = newdata, type = "response")
  }
  
  return(as.numeric(pred))
}
```
# 5. CALCULATE SHAP VALUES
```{r}
# Calculate SHAP values using fastshap
shap_values <- fastshap::explain(
  object = fitted_model,
  X = as.data.frame(test_sample),
  pred_wrapper = pred_wrapper,
  nsim = 50,  # Number of Monte Carlo samples (increase for more accuracy)
  adjust = TRUE
)
```
# 6. FEATURE IMPORTANCE (MEAN ABSOLUTE SHAP)
# Calculate mean absolute SHAP for each feature
```{r}
mean_abs_shap <- colMeans(abs(shap_values), na.rm = TRUE)
```
```{r}
# Create importance data frame
importance_df <- tibble(
  feature = names(mean_abs_shap),
  importance = mean_abs_shap
) %>%
  arrange(desc(importance))
```
```{r}
cat("✓ Top 10 features by SHAP importance:\n\n")

print(importance_df %>% head(10), n = 10)
importance_df
```
# Save importance
```{r}
write_csv(importance_df, "reports/shap_importance.csv")
cat("\n✓ SHAP importance saved to reports/shap_importance.csv\n\n")
```
# 7. VISUALIZATIONS
```{r}
# Create reports/figures directory if it doesn't exist
dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
```
# 7.1 Feature Importance Bar Plot
```{r}
p1 <- ggplot(importance_df %>% head(20), 
             aes(x = reorder(feature, importance), y = importance)) +
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
```
```{r}
# 7.2 SHAP Summary Plot (Beeswarm-style)
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
  filter(feature %in% importance_df$feature[1:15])  # Top 15 features
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

````
# 7.3 Dependence Plots for Top 5 Features
```{r}
cat("\nCreating dependence plots for top 5 features...\n")

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
````
# 8. BUSINESS INSIGHTS

```{r}
top5 <- importance_df %>% head(5)

cat("TOP 5 CHURN DRIVERS:\n\n")

for (i in 1:nrow(top5)) {
  feature_name <- top5$feature[i]
  importance_val <- top5$importance[i]
  
  # Calculate correlation between feature value and SHAP value
  feature_idx <- which(colnames(shap_values) == feature_name)
  if (length(feature_idx) > 0) {
    correlation <- cor(test_sample[[feature_name]], shap_values[, feature_idx], use = "complete.obs")
    direction <- ifelse(correlation > 0, "Higher", "Lower")
    
    cat(sprintf("%d. %s\n", i, feature_name))
    cat(sprintf("   Mean |SHAP|: %.4f\n", importance_val))
    cat(sprintf("   Direction: %s values → Higher churn risk\n", direction))
    cat(sprintf("   Correlation: %.3f\n\n", correlation))
  }
}
````
```{r}
cat("\n=============================================================\n")
cat("✓ MODEL INTERPRETATION COMPLETE!\n")
cat("=============================================================\n\n")

cat("OUTPUTS GENERATED:\n")
cat("✓ reports/shap_importance.csv\n")
cat("✓ reports/figures/shap_importance.png\n")
cat("✓ reports/figures/shap_summary.png\n")
cat("✓ reports/figures/shap_dependence_*.png (top 5 features)\n\n")
````
```{r}
library(tidyverse)
library(yardstick)
install.packages("gt")
library(gt) 
library(gridExtra)
```
```{r}
# 1. Load predictions
train <- read_csv("data/processed/features_selected.csv")
spl<-initial_split(train,strata=churn);test<-testing(spl)
model<-readRDS("models/xgb.rds")
prob<-predict(model,test,type="prob")$.pred_1
ch <- test$churn
```
```{r}
# 2. Baseline
bl_churn<-sum(ch); cat("Baseline churn:",bl_churn,"\n")
```
```{r}
# 3. Threshold optimization
ths<-seq(0.1,0.9,by=0.05)
res<-map_df(ths,~{
  pr<-.x; pred<-ifelse(prob>=pr,1,0)
  cm<-table(factor(pred,0:1),factor(ch,0:1))
  tp<-cm["1","1"];fp<-cm["1","0"];fn<-cm["0","1"]
  ret<-tp*0.7; rev<-ret*15000; cost<-(tp+fp)*1040
  tibble(threshold=.x,net=rev-cost,roi=(rev-cost)/cost*100)
})
write_csv(res,"reports/threshold_analysis.csv")
# Plot
p1<-ggplot(res,aes(threshold,roi))+geom_line()+geom_point()
p2<-ggplot(res,aes(threshold,net/1000))+geom_line()+geom_point()
png("reports/figures/business_thr.png",width=800,height=400)
grid.arrange(p1,p2,ncol=2); dev.off()

```
```{r}
# 4. Segmentation & summary
opt<-res[which.max(res$net),]
cat("Optimal threshold:",opt$threshold,"\nNet benefit:",opt$net,"\nROI:",opt$roi,"%\n")
```
```{r}
# Save results
gt(res) %>% gtsave("reports/business_analysis.html")
```
```{r}
# Enhanced Business Analysis with Segmentation

# 5. Customer Risk Segmentation
segments <- test %>%
  mutate(
    risk_score = prob,
    segment = case_when(
      risk_score >= 0.7 ~ "HIGH RISK",
      risk_score >= 0.4 ~ "MEDIUM RISK",
      risk_score >= 0.2 ~ "LOW RISK",
      TRUE ~ "VERY LOW"
    )
  ) %>%
  group_by(segment) %>%
  summarise(
    n_customers = n(),
    actual_churn_rate = mean(churn),
    avg_risk_score = mean(risk_score)
  )

write_csv(segments, "reports/customer_segments.csv")

# 6. Executive Summary
cat("\n=== EXECUTIVE SUMMARY ===\n")
cat("Total customers in test:", nrow(test), "\n")
cat("Baseline churners:", bl_churn, "\n")
cat("Optimal targeting threshold:", opt$threshold, "\n")
cat("Expected net benefit: €", format(opt$net, big.mark=","), "\n")
cat("Return on investment:", round(opt$roi, 1), "%\n")
cat("\nRECOMMENDATION: Implement 20% discount for customers with ≥", opt$threshold, "churn probability\n")

```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```
```{r}
```

