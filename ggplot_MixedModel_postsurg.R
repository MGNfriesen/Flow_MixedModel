library(readxl)
library(dplyr)
library(lme4)
library(ggplot2)
library(nlme)
library(reshape)
library(ggeffects) 


# Load data from Castor
#flow data (repeated measures)
df <- read_excel("~/Downloads/NECTAR_Necrotizing_Enterocolitis_excel_export_20230114104407.xlsx")
#clinical data
timing_castor <- read_excel("~/Downloads/NECTAR_Necrotizing_Enterocolitis_excel_export_20230208011705.xlsx")
#diagnosis 
Diagnosegroep <- read_excel("~/Downloads/Diagnoses en OKs Morgan tijdelijk.xlsx")


# Merge dataframes based on Participant Id
Diagnosegroep$`Participant Id`<- as.character(Diagnosegroep$`Participant Id`)
total_data <- df %>%
  left_join(timing_castor, by = "Participant Id") %>%
  left_join(Diagnosegroep, by = "Participant Id") %>%
  select(-matches(".*\\.(x|y)$"))

total_data$Participant.Id<-total_data$`Participant Id`

# Add flow measurements
total_data <- total_data %>%
  mutate(
    pi = ifelse(ultr_aca_angle == 1, ultr_aca_pi_no_ac_right_angle, ultr_aca_pi_with_ac),
    ri = ifelse(ultr_aca_angle == 1, ultr_aca_ri_no_ac_right_angle, ultr_aca_ri_with_ac),
    ps = ifelse(ultr_aca_angle == 1, ultr_aca_ps_no_ac_right_angle, ultr_aca_ps_with_ac),
    md = ifelse(ultr_aca_angle == 1, ultr_aca_md_no_ac_right_angle, ultr_aca_md_with_ac),
    pi = as.numeric(pi),
    ri = as.numeric(ri),
    ps = as.numeric(ps),
    md = as.numeric(md)
  )

# Add brain injury information
total_data <- total_data %>%
  mutate(
    bd_pre = ifelse(preop_mri_avail == 1, preop_bd_mri, preop_bd_echo),
    bd_post = ifelse(postop_mri_available == 1, postop_bd_mri, NA),
    bd_total = as.numeric(bd_pre == 1 | bd_post == 1)
  )

# Delete excluded patients
excluded_ids <- c("110007", "110011", "110012", "110019")
total_data <- total_data %>%
  filter(!Participant.Id %in% excluded_ids)

# Prepare data for mixed effect analyses
total_data$age_time_ultr<-as.numeric(total_data$age_time_ultr)
total_data$surg_age<-as.numeric(total_data$surg_age)
total_data$tim_ultr <- total_data$age_time_ultr-total_data$surg_age
total_data$bd_total<-as.factor(total_data$bd_total)




#Intercept
intercept <-gls(md ~ 1, data = total_data, method =
                  "ML", na.action = na.exclude)

#vary intercept accross patients
randomIntercept <- lme(md ~ 1, data = total_data,
                       random = ~1|Participant.Id, method = "ML", na.action = na.exclude, 
                       control = list(opt="optim"))


#adding random slopes: which means that intercepts and the effect of time (~Time) vary across people
timeRS<-update(randomIntercept, random = ~tim_ultr|Participant.Id)

#add covariance time
ARModel<-update(timeRS, correlation = corAR1(value=0, form = ~tim_ultr|Participant.Id))
summary(ARModel)

#fixed effects time and diagnosis
Arm_TD<- update(ARModel, md ~ tim_ultr * Diagnosegroep)

Arm_TD_bd<-update(Arm_time_, .~. + bd_total)

anova( ARModel,Arm_time_)


####Plot mixed effects

(mm_plot <- ggplot(total_data, aes(x = tim_ultr, y = md, colour = Participant.Id)) +
    facet_wrap(~Diagnosegroep, nrow=2) +   # a panel for each mountain range
    geom_point(alpha = 0.5) +
    theme_classic() +
    geom_line(data = cbind(total_data, pred = predict(Arm_TD)), aes(y = pred), linewidth = 1) +  # adding predicted line from mixed model 
    theme(legend.position = "none",
          panel.spacing = unit(2, "lines"))+
    labs(x = "day of ultrasound", y = "md", 
         title = ""))

Arm_TD_bd$tim_ultr<-as.numeric(Arm_TD_bd$tim_ultr)
# Extract the prediction data frame
mean.mm <- ggemmeans(Arm_TD, terms = c("tim_ultr","Diagnosegroep"))  # this gives overall means for the model
pred1<-ggpredict(ARModel, terms = c("tim_ultr","Diagnosegroep"))

(ggplot(pred1) + 
    geom_line(aes(x = x, y = predicted)) +
    geom_ribbon(aes(x = x, ymin = predicted - std.error, ymax = predicted + std.error), 
                fill = "lightgrey", alpha = 0.5) +  # error band
    geom_point(data = total_data,                      # adding the raw data (scaled values)
               aes(x = tim_ultr, y = md, colour = bd_total))  + xlim(-4,6)+ylim(-10,35)+
    labs(x = "Day of ultrasound", y = "Peak systolic velocity (cm/s)", 
         title = "") + 
    theme_minimal()
)






