
setwd("C:/Users/baouc/OneDrive - Bournemouth University/Master/Performance Mgt/R/Case studies")
# PowerCo Customer Churn Prediction – Exploratory Data Analysis
#!/usr/bin/env Rscript
# 01_EDA.R - PowerCo Customer Churn Prediction
# Exploratory Data Analysis (EDA)
# ==============================================

# Libraries
library(tidyverse)
library(skimr)
library(yardstick)
library(corrplot)
library(VIM)
library(gridExtra)

# 1. Load data --------------------------------------------------------------
train <- read_csv("ml_case_training_data.csv")
hist  <- read_csv("ml_case_training_hist_data.csv")
out   <- read_csv("ml_case_training_output.csv")
df <- train %>% left_join(out, by="id") %>% left_join(hist, by="id")

# 2. Missing Values ---------------------------------------------------------
mv <- df %>%
  summarise(across(everything(), ~sum(is.na(.)))) %>%
  pivot_longer(everything(), names_to="var", values_to="missing") %>%
  filter(missing > 0)

print(mv)

if(nrow(mv) > 0){
  aggr_plot <- aggr(df, prop=FALSE, numbers=TRUE)
  dir.create("reports/figures", recursive=TRUE, showWarnings=FALSE)
  png("reports/figures/missing_data.png", width=800, height=600)
  plot(aggr_plot); dev.off()
}

# 3. Numerical Distributions ------------------------------------------------
nums <- c("cons_12m", "cons_last_month", "net_margin", "forecast_discount_energy")

for(col in nums){
  if(col %in% names(df)){
    p <- ggplot(df, aes_string(x=col, fill="factor(churn)")) +
      geom_density(alpha=0.5) +
      theme_minimal() +
      scale_fill_manual(values=c("#2ecc71","#e74c3c")) +
      labs(title=paste("Distribution of", col))
    ggsave(paste0("reports/figures/dist_", col, ".png"), p, width=6, height=4)
  }
}

# 4. Correlation Matrix -----------------------------------------------------
corr_cols <- intersect(c(nums, "churn"), names(df))
cm <- df %>% select(all_of(corr_cols)) %>% cor(use="complete.obs")
png("reports/figures/corr.png", 800, 800)
corrplot(cm, method="color")
dev.off()

# 5. T-Tests ---------------------------------------------------------------
for(col in nums){
  if(col %in% names(df)){
    g0 <- df %>% filter(churn == 0) %>% pull(col)
    g1 <- df %>% filter(churn == 1) %>% pull(col)
    if(length(g0) > 10 & length(g1) > 10){
      t <- t.test(g0, g1)
      cat(col, ": p=", round(t$p.value, 4), "\n")
    }
  }
}

# 6. Data Summary ----------------------------------------------------------
skim(df)

cat("\nEDA complete: missing values, distribution plots, correlation, and statistical tests saved to reports/figures.")


