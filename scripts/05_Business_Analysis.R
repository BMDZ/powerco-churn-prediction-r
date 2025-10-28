# 05_Business_Analysis.R - PowerCo Customer Churn Business Impact
# ROI and Strategic Recommendations
# =================================================

library(tidyverse)
library(gt)
library(gridExtra)

# 1. Load predictions and test set --------------------------------------------
train <- read_csv("data/processed/features_selected.csv")
set.seed(42)
split <- initial_split(train, strata = churn)
test <- testing(split)

# 2. Load best model and predict churn probabilities ------------------------
model <- readRDS("models/xgb.rds")
prob <- predict(model, test, type = "prob") %>% pull(.pred_1)
ch <- test$churn

# 3. Baseline churn count ----------------------------------------------------
bl_churn <- sum(as.numeric(ch))

cat("Baseline churn (positive class count):", bl_churn, "\n")

# 4. Threshold optimization -------------------------------------------------
ths <- seq(0.1, 0.9, by = 0.05)
res <- map_df(ths, ~{
  pr <- .x
  pred <- ifelse(prob >= pr, 1, 0)
  cm <- table(factor(pred, levels=0:1), factor(ch, levels=0:1))
  tp <- cm["1", "1"]
  fp <- cm["1", "0"]
  fn <- cm["0", "1"]
  ret <- tp * 0.7          # 70% retention rate assumption
  rev <- ret * 15000       # €15,000 avg customer value
  cost <- (tp + fp) * 1040 # 20% discount cost on targeted customers
  tibble(threshold = pr, net = rev - cost, roi = (rev - cost) / cost * 100)
})

write_csv(res, "reports/threshold_analysis.csv")

# 5. Plot results ------------------------------------------------------------
p1 <- ggplot(res, aes(threshold, roi)) + geom_line() + geom_point() + 
  ggtitle("ROI by Churn Probability Threshold") + theme_minimal()

p2 <- ggplot(res, aes(threshold, net / 1000)) + geom_line() + geom_point() + 
  ggtitle("Net Benefit (€ thousands) by Threshold") + theme_minimal()

dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
png("reports/figures/business_thr.png", width = 800, height = 400)
grid.arrange(p1, p2, ncol = 2)
dev.off()

# 6. Optimal threshold summary ----------------------------------------------
opt <- res[which.max(res$net), ]
cat("Optimal threshold:", opt$threshold, "\n")
cat("Net benefit: €", format(opt$net, big.mark = ","), "\n")
cat("ROI: ", round(opt$roi, 2), "%\n")

# 7. Customer segmentation --------------------------------------------------
segments <- test %>%
  mutate(risk_score = prob,
         segment = case_when(
           risk_score >= 0.7 ~ "HIGH RISK",
           risk_score >= 0.4 ~ "MEDIUM RISK",
           risk_score >= 0.2 ~ "LOW RISK",
           TRUE ~ "VERY LOW"
         )) %>%
  group_by(segment) %>%
  summarise(
    n_customers = n(),
    actual_churn_rate = mean(as.numeric(churn))
  )

write_csv(segments, "reports/customer_segments.csv")

# Generate and save a summary table in HTML
gt(segments) %>% gtsave("reports/customer_segmentation.html")

# 8. Executive summary -------------------------------------------------------
cat("\n=== EXECUTIVE SUMMARY ===\n")
cat("Total customers in test:", nrow(test), "\n")
cat("Baseline churners:", bl_churn, "\n")
cat("Optimal targeting threshold:", opt$threshold, "\n")
cat("Expected net benefit: €", format(opt$net, big.mark = ","), "\n")
cat("Return on investment:", round(opt$roi, 1), "%\n")
cat("\nRECOMMENDATION: Implement 20% discount for customers with ≥", opt$threshold, "churn probability\n")

cat("\n✓ Business analysis completed. Results saved in reports/.\n")

