################################################################################
#                                                                              #
# Purpose:       Parvo Plot Script                                             #
#                                                                              #
# Author:        Philipp Reyher                                                #
# Contact:       reyher.philipp@gmail.com                                      #
# Client:        Philipp Reyher                                                #
#                                                                              #
# Code created:  2022-10-28                                                    #
# Last updated:  2022-10-28                                                    #
# Source:        C:/Users/reyhe/Documents/Parvo                                #
#                                                                              #
# Comment:       Script aims to automise the creation of plots using the Parvo #
#                Metabolic Cart data                                           #
#                                                                              #
################################################################################
################################### Packages ###################################
library(purrr)
library(data.table)
library(tidytable)
library(ggplot2)
library(signal)
library(gridExtra)
library(grid)
library(here)
#################################### Import ####################################
##get dir that script is in
dir <- dirname(here::here())
setwd(dir)
file.list = list.files(path = "data/single", pattern = "*.csv", ignore.case = T,
    full.names = T)

##read data
##apply over file-list
test_data <- lapply(file.list, function(x){ 
  df <- fread(x, header = F, fill = T, sep = ",", quote = "\"", dec = ".",
  na.strings = "")
  df
  })

################### Extract demographics and test parameters ###################
##function to perform regex search x must be a regular expression as a string,
##which is then searched for within the dataset
##y is optional, input 1 so the value 'left' to the searched cell is extracted,
##instead of the default: 'right'
regex_s <- function (df,x,y=0,unit="kg"){
  
  if (unit != "kg" & unit != "lb") {
    stop("Invalid value for unit. Must be 'kg' or 'lbs'.")
  }
  ##Find column name and row index of demographics with regex
  ##Outputs a list with elemts containing row index and the name of the
  ##elements containing the columnname!
  tmp <- sapply(df, function(col) {
    grep(x,col,perl = T,ignore.case = T)
  })
  ##find column index within list as column name is impractical for the
  ##following steps
  tmp_col <- as.integer(which(tmp != 0))
  
  
  if(all(sapply(tmp, is.null)) == 1){
    return(NA_character_)
    stop()
  }
  ##Find row index within list using column index
  tmp_row <- as.integer(tmp[tmp_col])
  ##special case weight, z specifies unit, default "kg"
  if(grepl("weight", x)){tmp_col <- grep(unit,tolower(df[tmp_row,])) - 1}
  ##Should the value be left of the demographics' name
  else if(y=="1"){tmp_col <- tmp_col - 1}
  ##Should the value be right to the demographics' name (default)
  else{tmp_col <- tmp_col + 1}
  ##extract from dataframe using both indices
  
  return(as.character(df[tmp_row,..tmp_col])
  )}


##save participant names in array for later
partnames <- sapply(test_data, function(df) {
  NAME <- regex_s(df,"\\bname\\b")
})

names(test_data) <- partnames

demo_data <- lapply(test_data, function(df) {
  NAME <- regex_s(df,"\\bname\\b")
  AGE <- regex_s(df,"\\bage\\b")
  SEX <- regex_s(df,"\\bsex\\b")
  MASS <- regex_s(df,"\\bweight\\b",unit="kg")
  DEVICE <- regex_s(df,"^(?=.*(exercise))(?=.*(device)).*$")
  PB <- regex_s(df,"^(?=.*(baro))(?=.*(press)).*$")
  TEMP <- regex_s(df,"^(?=.*(insp))(?=.*(temp)).*$")
  RH <- regex_s(df,"^(?=.*(insp))(?=.*(humid)).*$")
  EV_WU <- regex_s(df,"^(?=.*(warm))(?=.*(up)).*$",1)
  ifelse(length(EV_WU)==0,EV_WU <- NA,EV_WU)
  EV_EX <- regex_s(df,"^(?=.*(start))(?=.*(exercise)).*$",1)
  ifelse(length(EV_EX)==0,EV_EX <- NA,EV_EX)
  EV_CD <- regex_s(df,"^(?=.*(cool))(?=.*(down)).*$",1)
  ifelse(length(EV_CD)==0,EV_CD <- NA,EV_CD)
  
  df1 <- data.frame(NAME, AGE, SEX, MASS, DEVICE, PB, TEMP, RH, EV_WU, EV_EX,
                    EV_CD)
  df1 <- df1 %>% select(where(~any(!is.na(.))))
  })
  
##function to extract the dates from file.list and append it to the demographics
##list
##apply over both lists
demo_data <- mapply(df = demo_data, x = file.list, SIMPLIFY = F,
  FUN = function(df,x){
  dat <- regmatches(x, regexpr("\\d{8}", x))
  df$TEST_DAT <- as.Date(dat, format = "%Y%m%d")
  df
  })

################################ Clean dataset #################################
test_data <- lapply(test_data, function(df) {
  ##find indices of string "time", this is where the spiro data starts
  tmp <- which(sapply(df, function(x) {grepl("TIME",fixed = T,x)}) )-1
  ##finally remove the mess from the top
  df <- slice(df,-(1:tmp) )
  ##Column names
  ##combine the two header rows
  coln <- paste(df[1,],df[2,],sep = "")
  ## clean up NAs
  coln <- gsub("NA","",coln)
  ##remove whitespace
  coln <- gsub(" ","",coln)
  ##standardize colnames
  coln <- sub("^(?=.*(VO2))(?=.*(kg)).*$","VO2_REL",coln,perl = T,
              ignore.case = T)
  coln <- sub("VO2STPD","VO2_ABS",coln,perl = T,ignore.case = T)
  coln <- sub(".*work.*","WORK",coln,perl = T,ignore.case = T)
  coln <- sub(".*hr.*","HR",coln,perl = T,ignore.case = T)
  
  coln <- toupper(gsub("STPD","",coln))
  colnames(df) <- coln
  ##remove anything but data
  df <- slice(df,-(1:4) )
  ##find first and last instance of NA to remove mess at the bottom
  NAindex <- which(is.na(df[,1]))
  firstNA <- min(NAindex)
  l <- nrow(df)
  df <- slice(df,-(firstNA:l) )
  ##convert time from m:s format to s
  TIME_S <- lubridate::ms(df$TIME)
  TIME_S <- lubridate::period_to_seconds(TIME_S)
  df <- cbind(df[, 1], TIME_S, df[, 2:ncol(df)])
  ##change to POSIXct for graphing later
  df$TIME <- as.POSIXct(strptime(df$TIME, format= "%M:%S"))
  ##convert all to numeric, to character first to preserve factors
  df <-df %>% mutate(across(.cols = !TIME, ~ as.character(.x) %>% 
                              as.numeric(.x) ) )
  ##rename problematic column names
  df <- df %>% rename('VE_VO2'=`VE/VO2`,'VE_VCO2'=`VE/VCO2`)
  
  df
})

########################## Smoothing, computation of vars ######################
test_data <- lapply(test_data,function(df) {
  bf <- butter(3, 0.04, type= 'low')
  df$VO2_ABS_LOW <- signal::filtfilt(bf, df$VO2_ABS)
  df$VO2_REL_LOW <- signal::filtfilt(bf, df$VO2_REL)
  
  df$VCO2_LOW <- signal::filtfilt(bf, df$VCO2)
  
  df$VE_LOW <- signal::filtfilt(bf, df$VE)
  
  df$VE_VO2_LOW <- signal::filtfilt(bf, df$VE_VO2)
  
  df$VE_VCO2_LOW <- signal::filtfilt(bf, df$VE_VCO2)
  
  
  f15 <- rep(1/15,15)
  df$VO2_ABS_SMA <- stats::filter(df$VO2_ABS, f15, method = "convolution",
                                  sides = 2, circular = TRUE)
  
  f30 <- rep(1/30,30)
  df$VE_VO2_SMA <- stats::filter(df$VE_VO2, f30, method = "convolution",
                                 sides = 2, circular = TRUE)
  
  df$VE_VCO2_SMA <- stats::filter(df$VE_VCO2, f30, method = "convolution",
                                  sides = 2, circular = TRUE)
  
  #df$VE_VO2_LOW <- df$VE_LOW/df$VO2_ABS_LOW
  #df$VE_VCO2_LOW <- df$VE_LOW/df$VCO2_LOW
  
  
  df$EXCO2 <- ( ( (df$VCO2*df$VCO2)/df$VO2_ABS) - df$VCO2)
  df$EXVE <- ( ( (df$VE*df$VE)/df$VCO2) - df$VE)
  
  df$EXCO2_LOW <- ( ( (df$VCO2_LOW*df$VCO2_LOW)/df$VO2_ABS_LOW) - df$VCO2_LOW)
  df$EXVE_LOW <- ( ( (df$VE_LOW*df$VE_LOW)/df$VCO2_LOW) - df$VE_LOW)
  
  #no forgetti removi!!!
  df$HR <- 100
  
  df
})

############################# extend demo data #################################
demo_data <- mapply(df=test_data, dem=demo_data, SIMPLIFY = F,
                    FUN= function(df,dem){
                      ev_ex <- as.numeric(dem$EV_EX)*60
                      ev_cd <- as.numeric(dem$EV_CD)*60
                      beg <- which.max(df$TIME_S >= ev_ex)
                      end <- which.max(df$TIME_S >= ev_cd)
                      dem$EV_EX_I <- beg
                      dem$EV_CD_I <- end
                      dem
                    })

################################## Truncation ##################################
test_data_trunc <- mapply(df=test_data, dem=demo_data, SIMPLIFY = F,
                    FUN= function(df,dem){
                    
                    out <- df%>% slice(dem$EV_EX_I:dem$EV_CD_I)
                    
                    out
                  })

############################ Interpolation, Binning ############################
#interpolation
test_data_sec <- lapply(test_data_trunc, function(df){
  interpolate <- function(df) {
    ## first make sure data only contains numeric columns
    data_num <- df %>%
      select(where(is.numeric))
    
      out <- lapply(data_num, \(i) approx(
        x = data_num[[1]],
        y = i,
        xout = seq(min(data_num[[1]]), max(data_num[[1]], na.rm = TRUE), 1)
      )$y
      ) %>%
        as.data.frame()
    
    out
  }
  out <- interpolate(df)
  out
  })
#binning
bin <- function(df,bin){
  
  data_num <- df %>%
    select(where(is.numeric))
  
  out <- data_num %>%
    mutate(across(1,\(x) round(x / bin) * bin)) %>% 
    group_by(1) %>%
    summarise(across(everything(),mean, na.rm = TRUE) )
  out
}

test_data_10bin <- lapply(test_data_sec, \(df) bin(df,10) )

####################### Calculation of VT1, VT2 ################################
findchangepts_std <- function(x) {
  m <- nrow(x)
  n <- ncol(x)
  max_log_likelihood <- -Inf
  change_point <- 0
  for (i in 3:(n-2)) {
    log_likelihood <- 0
    for (j in 1:m) {
      region1 <- x[j, 1:(i-1)]
      region2 <- x[j, i:n]
      std1 <- sd(region1)
      std2 <- sd(region2)
      mean1 <- mean(region1)
      mean2 <- mean(region2)
      log_likelihood1 <- sum(dnorm(region1, mean = mean1, sd = std1,
                                   log = TRUE))
      log_likelihood2 <- sum(dnorm(region2, mean = mean2, sd = std2,
                                   log = TRUE))
      log_likelihood <- log_likelihood + log_likelihood1 + log_likelihood2
    }
    if (log_likelihood > max_log_likelihood) {
      max_log_likelihood <- log_likelihood
      change_point <- i
    }
  }
  return(change_point)
}

predict_work <- function(df,VO2_VAL){
  df <- df %>% slice(1:which.max(df$WORK))
  model <- lm(WORK ~ VO2_ABS_LOW,data = df)
  new_observations <- data.frame(VO2_ABS_LOW=VO2_VAL)
  predicted_vals <- predict(model,newdata = new_observations)
  return(predicted_vals)
}

cps_input <- function(test_data){
  lapply(test_data, function(df){
  ##truncate dataframe to ranges in which VT1/VT2 can occur (NASA Paper,2021)
  vt1_i_beg <- which.min( abs(df$TIME_S-quantile(df$TIME_S,0.3)))
  vt1_i_end <- which.min( abs(df$TIME_S-quantile(df$TIME_S,0.8)))
  vt2_i_beg <- which.min( abs(df$TIME_S-quantile(df$TIME_S,0.5)))
  
  df_vt1 <- df %>% slice(vt1_i_beg:vt1_i_end)
  df_vt2 <- df %>% slice_tail(n=vt2_i_beg+1)
  ##breakpointanalyses
  ##VT1##
  ##V-Slope##
  vslop <- df_vt1 %>% select(VO2_ABS_LOW,VCO2_LOW) %>% as.matrix(.) %>% t(.)
  VT1VSLOP_I <- findchangepts_std(vslop)+vt1_i_beg-1
  #EXCO2##
  exco2 <- df_vt1 %>% select(EXCO2) %>% as.matrix(.) %>% t(.)
  VT1EXCO2_I <- findchangepts_std(exco2)+vt1_i_beg-1
  ##VT2##
  ##V-Slope##
  vslop2 <- df_vt2 %>% select(VCO2,VE) %>% as.matrix(.) %>% t(.)
  VT2VSLOP_I <- findchangepts_std(vslop2)+vt2_i_beg-1
  ##EXVE##
  exve <- df_vt2 %>% select(EXVE) %>% as.matrix(.) %>% t(.)
  VT2EXVE_I <- findchangepts_std(exve)+vt2_i_beg-1
  ##combine
  VT1_I <- round((VT1EXCO2_I+VT1VSLOP_I)/2)
  VT2_I <- round((VT2EXVE_I+VT2VSLOP_I)/2)
  VT1_TIME <- df$TIME_S[VT1_I]
  VT2_TIME <- df$TIME_S[VT2_I]
  VT1_VO2ABS <- df$VO2_ABS_LOW[VT1_I]
  VT2_VO2ABS <- df$VO2_ABS_LOW[VT2_I]
  VT1_VO2REL <- df$VO2_REL_LOW[VT1_I]
  VT2_VO2REL <- df$VO2_REL_LOW[VT2_I]

  VT1_WORK <- predict_work(df,VT1_VO2ABS)
  VT2_WORK <- predict_work(df,VT2_VO2ABS)
  
  VT1_HR <- df$HR[VT1_I]
  VT2_HR <- df$HR[VT2_I]
  
  VT1_VO2PERC <- df$VO2_ABS_LOW[VT1_I]
  VT2_VO2PERC <- df$VO2_ABS_LOW[VT2_I]
  VT1_WORKPERC <- VT1_WORK
  VT2_WORKPERC <- VT2_WORK
  VT1_HRPERC <- df$HR[VT1_I]
  VT2_HRPERC <- df$HR[VT2_I]
  
  df <- data.frame(VT1EXCO2_I, VT1VSLOP_I,VT2EXVE_I, VT2VSLOP_I,
                   VT1_I,VT2_I,  VT1_TIME,VT2_TIME,  VT1_VO2ABS,VT2_VO2ABS,
                   VT1_VO2REL,VT2_VO2REL,  VT1_WORK,VT2_WORK,  VT1_HR,VT2_HR,
                   VT1_VO2PERC,VT2_VO2PERC,  VT1_WORKPERC,VT2_WORKPERC,  
                   VT1_HRPERC,VT2_HRPERC)
  df
    })
}

cps_10bin <- cps_input(test_data_10bin)

####################### Changepoints plotting ##################################
#plotting function
plist_cps_func <- function(test_data,cps_data){
  plist <- mapply(df=test_data, vt=cps_data, SIMPLIFY = F,
                  FUN = function(df,vt)
        {
         exco2 <- ggplot(df, aes(x=TIME_S))+
           geom_point(aes(y=EXCO2),colour='blue')+
           geom_vline(xintercept = df$TIME_S[vt$VT1EXCO2_I], colour='green')+
           annotate(x=df$TIME_S[vt$VT1EXCO2_I],y=+Inf,
                    label=paste0("VT1=",df$TIME_S[vt$VT1EXCO2_I]," s"),
                    vjust=2,geom="label")+
           theme_bw()
         
         vslop1 <- ggplot(df, aes(x=VO2_ABS))+
           geom_point(aes(y=VCO2),colour='blue')+
           geom_vline(xintercept = df$VO2_ABS[vt$VT1VSLOP_I], colour='green')+
           annotate(x=df$VO2_ABS[vt$VT1VSLOP_I],y=+Inf,
                    label=paste0("VT1=",df$TIME_S[vt$VT1VSLOP_I]," s"),
                    vjust=2,geom="label")+
           theme_bw()
         
         exve <- ggplot(df, aes(x=TIME_S))+
           geom_point(aes(y=EXVE),colour='blue')+
           geom_vline(xintercept = df$TIME_S[vt$VT2EXVE_I], colour='green')+
           annotate(x=df$TIME_S[vt$VT2EXVE_I],y=+Inf,
                    label=paste0("VT2=",df$TIME_S[vt$VT2EXVE_I]," s"),
                    vjust=2,geom="label")+
           theme_bw()
         
         vslop2 <- ggplot(df, aes(x=VCO2))+
           geom_point(aes(y=VE),colour='blue')+
           geom_vline(xintercept = df$VCO2[vt$VT2VSLOP_I], colour='green')+
           annotate(x=df$VCO2[vt$VT2VSLOP_I],y=+Inf,
                    label=paste0("VT2=",df$TIME_S[vt$VT2VSLOP_I]," s"),
                    vjust=2,geom="label")+
           theme_bw()
         
         bigplot <- ggplot(df, aes(x=TIME_S))+
           coord_cartesian(xlim = c(300, 1100),ylim = c(7.5,45))+
           scale_x_continuous(name="Time (s)",
                              breaks=seq(300,1150,50) )+
           scale_y_continuous(name="VE/VO2 | VE/VCO2", breaks=seq(10,45,5),
           sec.axis = sec_axis(~.*10,name='Work' ) )+
           geom_point(aes(y=VE_VO2, colour='VE/VO2') )+
           geom_point(aes(y=VE_VCO2, colour='VE/VCO2') )+
           geom_vline(xintercept = df$TIME_S[vt$VT1_I],colour='black',
                      linetype = "dotted")+
           annotate(x=df$TIME_S[vt$VT1_I],y=+Inf,
                    label=paste0("VT1=",df$TIME_S[vt$VT1_I]," s"),
                    vjust=2,geom="label")+
           geom_vline(xintercept = df$TIME_S[vt$VT2_I],colour='green',
                      linetype = "longdash")+
           annotate(x=df$TIME_S[vt$VT2_I],y=+Inf,
                    label=paste0("VT2=",df$TIME_S[vt$VT2_I]," s"),
                    vjust=2,geom="label")+
           geom_area(aes(y = (WORK/10),colour="Work"), fill ="lightblue", 
                     alpha = 0.4) +
           scale_color_manual(name=' ',
                          breaks=c('VE/VO2', 'VE/VCO2', 'Work'),
              values=c('VE/VO2'='blue', 'VE/VCO2'='red', 'Work'='lightblue'),
              guides(colour = guide_legend(override.aes = list(size = 8) ) ) )+
          theme_bw()+
           guides(shape = guide_legend(override.aes = list(size = 1)))+
           guides(color = guide_legend(override.aes = list(size = 1)))+
           theme(legend.title = element_blank(),
                 legend.text = element_text(size = 8),
                 legend.position = c(.05, .95),
                 legend.justification = c("left", "top"),
                 legend.box.just = "right",
                 legend.margin = margin(6, 6, 6, 6) )
         
         plots <- list(exco2,vslop1,exve,vslop2,bigplot)
         lay <- rbind(c(1,1,2,2),
                      c(1,1,2,2),
                      c(3,3,4,4),
                      c(3,3,4,4),
                      c(5,5,5,5),
                      c(5,5,5,5),
                      c(5,5,5,5),
                      c(5,5,5,5),
                      c(5,5,5,5))

         out <- arrangeGrob(grobs = plots, layout_matrix = lay)
       })
  return(plist)
}
# #create plots
plist_cps_10bin <- plist_cps_func(test_data_10bin,cps_10bin)
# #save individual plots
partnames_formatted <- gsub(",", "_", partnames)
partnames_formatted <- gsub(" ", "", partnames_formatted)
purrr::pwalk(list(partnames_formatted,plist_cps_10bin), function(name,p){
  ggsave(paste0("./plots/individual_plots/",name,".pdf"), p, width = 11,
         height = 8.5, units = "in")
})
partnames_formatted <- as.list(partnames_formatted)

################################# Test Details #################################
details_tbl <- lapply(demo_data,function(dem){
  
  out <- dem %>% select(TEST_DAT,TEMP,RH,PB) %>%
    mutate(across(TEST_DAT,~format(.x, format = "%d-%b-%Y"))) %>% 
    mutate(across(2:4,~format(round(as.numeric(.),1), nsmall=1))) 
  out
  })

############################# Table summary ####################################
max_tbl <- lapply(test_data, function(df){
  
  MAX_I <- which.max(df$VO2_ABS_LOW)
  MAX_TIME <- df$TIME_S[MAX_I]
  MAX_VO2ABS <- max(df$VO2_ABS_LOW)
  MAX_VO2REL <- max(df$VO2_REL_LOW)
  MAX_WORK <- predict_work(df,MAX_VO2ABS)
  MAX_HR <- max(df$HR)
  
  MAX_VO2PERC <- 1
  MAX_WORKPERC <- 1
  MAX_HRPERC <- 1
  
  out <- data.frame(MAX_I,MAX_TIME,MAX_VO2ABS,MAX_VO2REL,MAX_WORK,MAX_HR,
                   MAX_VO2PERC,MAX_WORKPERC,MAX_HRPERC)
  out
  
})

summary_tbl <- mapply(cp=cps_10bin,max=max_tbl,SIMPLIFY = F,
                  FUN = function(cp,max){
  
  cp$VT1_VO2PERC <- cp$VT1_VO2PERC/max$MAX_VO2ABS
  cp$VT2_VO2PERC <- cp$VT2_VO2PERC/max$MAX_VO2ABS
  
  cp$VT1_WORKPERC <- cp$VT1_WORKPERC/max$MAX_WORK
  cp$VT2_WORKPERC <- cp$VT2_WORKPERC/max$MAX_WORK
  
  cp$VT1_HRPERC <- cp$VT1_HRPERC/max$MAX_HR
  cp$VT2_HRPERC <- cp$VT2_HRPERC/max$MAX_HR
  
  cp <- cbind(cp,max)
  
  cp <- select(cp, -c(VT1EXCO2_I,VT1VSLOP_I,VT2VSLOP_I,VT2EXVE_I)) %>%
  pivot_longer(everything(),names_sep = "_",
               names_to = c("VARIABLE","measurement")) %>%
  pivot_wider(id_cols =VARIABLE, names_from = measurement, values_from = value,
              names_repair = "check_unique")
  
  out <- cp[order(cp$VO2ABS),]
  out
})

summary_formatted_tbl <- lapply(summary_tbl, function(df){
  df <- df %>% mutate(across(ends_with("PERC",ignore.case =T),
                             ~round(.*100,digits = 0) ) ) %>%
    mutate(across(c("WORK","HR"),~round(.,digits = 0) )) %>% 
    mutate(across(c("VO2ABS","VO2REL"),~format(round(.,digits = 1),nsmall = 1)))
  out <- df %>% select(VARIABLE,WORK,WORKPERC,VO2ABS,VO2REL,VO2PERC,HR,HRPERC)
  
  out
})

#################################### GXT Table #################################
#add perc, for later gxt_tbl, function
test_data_trunc<- lapply(test_data_trunc, function(df){
  
  df$VO2MAX_PERC <- df$VO2_REL_LOW/max(df$VO2_REL_LOW)
  df$HRMAX_PERC <- df$HR/max(df$HR)
  df
})

gxt_tbl <- lapply(test_data_trunc, function(df){
  df <- df %>% slice(1:which.max(df$WORK))
  WORK <- df$WORK
  df <- select(df,VO2_ABS_LOW,VO2_REL_LOW,VO2MAX_PERC,HR,HRMAX_PERC)
  results_list <- lapply(df, function(vec){
    model <- lm(vec ~ WORK)
    WORK_IN <- seq(100,max(WORK),by=25)
    new_observations <- data.frame(WORK =  WORK_IN)
    predicted_vals <- predict(model,newdata = new_observations)
    })
  
  WORK = seq(100,max(WORK),by=25 )
  out <- bind_cols(results_list)
  out <- cbind(WORK,out)
  out <- out %>% 
    mutate(across(c("VO2MAX_PERC","HRMAX_PERC"), ~round(.*100,digits = 0))) %>% 
    mutate(across(c("WORK","HR"),~round(.,digits = 0)) ) %>% 
    mutate(across(c("VO2_ABS_LOW","VO2_REL_LOW"),~format(round(.,digits = 1),
                                                         nsmall = 1)) )
  out
})

#change last stage with max
gxt_tbl <- mapply(gxt=gxt_tbl,max=max_tbl,SIMPLIFY = F,function(gxt,max){
  gxt <- gxt[-nrow(gxt),]
  max <- max %>% select('WORK'=MAX_WORK,'VO2_ABS_LOW'=MAX_VO2ABS,
                        'VO2_REL_LOW'=MAX_VO2REL,'VO2MAX_PERC'=MAX_VO2PERC,
                        'HR'=MAX_HR,'HRMAX_PERC'=MAX_HRPERC) %>% 
    mutate(across(c("VO2MAX_PERC","HRMAX_PERC"), ~round(.*100,digits = 0))) %>% 
    mutate(across(c("WORK","HR"),~round(.,digits = 0)) ) %>% 
    mutate(across(c("VO2_ABS_LOW","VO2_REL_LOW"),~format(round(.,digits = 1)
                                                         ,nsmall = 1)) )
  out <- rbind(gxt,max)
  out
})

########################### Coggan Power Zones #################################
coggan_tbl <- lapply(cps_10bin, function(df){
  
  lvl1_work_low <- "-"
  lvl1_work_up <- round(df$VT2_WORK*0.55)
  lvl1_hr_low <- "-"
  lvl1_hr_up <- round(df$VT2_HR*0.68)
  lvl1_rpe_low <- "-"
  lvl1_rpe_up <- 9
  
  lvl2_work_low <- round(df$VT2_WORK*0.56)
  lvl2_work_up <- round(df$VT2_WORK*0.75)
  lvl2_hr_low <- round(df$VT2_HR*0.69)
  lvl2_hr_up <- round(df$VT2_HR*0.83)
  lvl2_rpe_low <- 9
  lvl2_rpe_up <- 11
  
  lvl3_work_low <- round(df$VT2_WORK*0.76)
  lvl3_work_up <- round(df$VT2_WORK*0.90)
  lvl3_hr_low <- round(df$VT2_HR*0.84)
  lvl3_hr_up <- round(df$VT2_HR*0.94)
  lvl3_rpe_low <- 11
  lvl3_rpe_up <- 13
  lvl4_work_low <- round(df$VT2_WORK*0.91)
  lvl4_work_up <- round(df$VT2_WORK*1.05)
  lvl4_hr_low <- round(df$VT2_HR*0.95)
  lvl4_hr_up <- round(df$VT2_HR*1.05)
  lvl4_rpe_low <- 13
  lvl4_rpe_up <- 15
  
  lvl5_work_low <- round(df$VT2_WORK*1.06)
  lvl5_work_up <- round(df$VT2_WORK*1.2)
  lvl5_hr_low <- round(df$VT2_HR*1.06)
  lvl5_hr_up <- "-"
  lvl5_rpe_low <- 15
  lvl5_rpe_up <- 17
  
  lvl6_work_low <- round(df$VT2_WORK*1.21)
  lvl6_work_up <- "-"
  lvl6_hr_low <- "-"
  lvl6_hr_up <- "-"
  lvl6_rpe_low <- 17
  lvl6_rpe_up <- 19
  
  lvl7_work_low <- "-"
  lvl7_work_up <- "-"
  lvl7_hr_low <- "-"
  lvl7_hr_up <- "-"
  lvl7_rpe_low <- 20
  lvl7_rpe_up <- "-"

  
  lvl1 <- c(1,"Active Recovery",lvl1_work_low,lvl1_work_up,lvl1_hr_low,
            lvl1_hr_up,lvl1_rpe_low,lvl1_rpe_up)
  lvl2 <- c(2,"Endurance",lvl2_work_low,lvl2_work_up,lvl2_hr_low,lvl2_hr_up,
            lvl2_rpe_low,lvl2_rpe_up)
  lvl3 <- c(3,"Tempo",lvl3_work_low,lvl3_work_up,lvl3_hr_low,lvl3_hr_up,
            lvl3_rpe_low,lvl3_rpe_up)
  lvl4 <- c(4,"Lactate Threshold",lvl4_work_low,lvl4_work_up,lvl4_hr_low,
            lvl4_hr_up,lvl4_rpe_low,lvl4_rpe_up)
  lvl5 <- c(5,"VO\\textsubscript{2max}",lvl5_work_low,lvl5_work_up,lvl5_hr_low,lvl5_hr_up,
            lvl5_rpe_low,lvl5_rpe_up)
  lvl6 <- c(6,"Anaerobic Capacity",lvl6_work_low,lvl6_work_up,lvl6_hr_low,
            lvl6_hr_up,lvl6_rpe_low,lvl6_rpe_up)
  lvl7 <- c(7,"Neuromuscular Power",lvl7_work_low,lvl7_work_up,lvl7_hr_low,
            lvl7_hr_up,lvl7_rpe_low,lvl7_rpe_up)
  tr_zones <- as.data.frame(rbind(lvl1,lvl2,lvl3,lvl4,lvl5,lvl6,lvl7))
  colnames(tr_zones) <- c("Zone","Intensity","Lower \\par Range",
                          "Upper \\par Range","Lower \\par Range",
                          "Upper \\par Range","Lower \\par Range",
                          "Upper \\par Range")
  rownames(tr_zones) <- NULL
  out <- tr_zones
  out
})

############################# AIS Power Zones ##################################
ais_tbl <- lapply(max_tbl, function(df){
  
  lvl0_work_low <-round(df$MAX_WORK*0.4)
  lvl0_work_up <- round(df$MAX_WORK*0.5)
  lvl0_hr_low <- "-"
  lvl0_hr_up <- round(df$MAX_HR*0.65)
  lvl0_rpe_low <- "-"
  lvl0_rpe_up <- 11
  
  lvl1_work_low <-round(df$MAX_WORK*0.5)
  lvl1_work_up <- round(df$MAX_WORK*0.65)
  lvl1_hr_low <- round(df$MAX_HR*0.65)
  lvl1_hr_up <- round(df$MAX_HR*0.75)
  lvl1_rpe_low <- 12
  lvl1_rpe_up <- 13
  
  lvl2_work_low <- round(df$MAX_WORK*0.65)
  lvl2_work_up <- round(df$MAX_WORK*0.725)
  lvl2_hr_low <- round(df$MAX_HR*0.75)
  lvl2_hr_up <- round(df$MAX_HR*0.8)
  lvl2_rpe_low <- 13
  lvl2_rpe_up <- 15
  
  lvl3_work_low <- round(df$MAX_WORK*0.725)
  lvl3_work_up <- round(df$MAX_WORK*0.80)
  lvl3_hr_low <- round(df$MAX_HR*0.8)
  lvl3_hr_up <- round(df$MAX_HR*0.85)
  lvl3_rpe_low <- 15
  lvl3_rpe_up <- 16
  
  lvl4_work_low <- round(df$MAX_WORK*0.8)
  lvl4_work_up <- round(df$MAX_WORK*0.9)
  lvl4_hr_low <- round(df$MAX_HR*0.85)
  lvl4_hr_up <- round(df$MAX_HR*0.92)
  lvl4_rpe_low <- 16
  lvl4_rpe_up <- 17
  
  lvl5_work_low <- round(df$MAX_WORK*0.9)
  lvl5_work_up <- round(df$MAX_WORK*1)
  lvl5_hr_low <- round(df$MAX_HR*0.92)
  lvl5_hr_up <- round(df$MAX_HR*1)
  lvl5_rpe_low <- 17
  lvl5_rpe_up <- 19
  
  lvl0 <- c(0,"Recovery",lvl0_work_low,lvl0_work_up,lvl0_hr_low,
            lvl0_hr_up,lvl0_rpe_low,lvl0_rpe_up)
  lvl1 <- c(1,"Aerobic",lvl1_work_low,lvl1_work_up,lvl1_hr_low,
            lvl1_hr_up,lvl1_rpe_low,lvl1_rpe_up)
  lvl2 <- c(2,"Extensive Endurance",lvl2_work_low,lvl2_work_up,lvl2_hr_low,lvl2_hr_up,
            lvl2_rpe_low,lvl2_rpe_up)
  lvl3 <- c(3,"Intensive Endurance",lvl3_work_low,lvl3_work_up,lvl3_hr_low,lvl3_hr_up,
            lvl3_rpe_low,lvl3_rpe_up)
  lvl4 <- c(4,"Threshold",lvl4_work_low,lvl4_work_up,lvl4_hr_low,
            lvl4_hr_up,lvl4_rpe_low,lvl4_rpe_up)
  lvl5 <- c(5,"VO\\textsubscript{2max}",lvl5_work_low,lvl5_work_up,lvl5_hr_low,lvl5_hr_up,
            lvl5_rpe_low,lvl5_rpe_up)
  tr_zones <- as.data.frame(rbind(lvl0,lvl1,lvl2,lvl3,lvl4,lvl5))
  colnames(tr_zones) <- c("Zone","Intensity","Lower \\par Range",
                          "Upper \\par Range","Lower \\par Range",
                          "Upper \\par Range","Lower \\par Range",
                          "Upper \\par Range")
  rownames(tr_zones) <- NULL
  out <- tr_zones
  out
})

############################## Exercise plots ##################################
ex_plots <- mapply(df=test_data,dem=demo_data,vt=cps_10bin,SIMPLIFY = F,
                  FUN=function(df,dem,vt){
  p <-  ggplot(df,aes(x=TIME_S))+
  
  geom_vline(xintercept = vt$VT1_TIME)+
  annotate(x=vt$VT1_TIME,y=+Inf,
  label="VT1",vjust=2,geom="label")+
  
  geom_vline(xintercept = vt$VT2_TIME)+
  annotate(x=vt$VT2_TIME,y=+Inf,
  label="VT2",vjust=2,geom="label")+
  
  geom_vline(xintercept = df$TIME_S[dem$EV_EX_I])+
  annotate(x=df$TIME_S[dem$EV_EX_I],y=+Inf,
  label="Start",vjust=2,geom="label")+
  
  geom_vline(xintercept = df$TIME_S[dem$EV_CD_I])+
  annotate(x=df$TIME_S[dem$EV_CD_I],y=+Inf,
  label="Cooldown",vjust=2,geom="label")+
  
  geom_line(aes(y=VO2_ABS_LOW,group=1, colour='VO2'))+
  guides(color = guide_legend(override.aes = list(size = 1.5)))+
  labs(color="Measurement")+
  geom_line(aes(y=VCO2_LOW,group=2, colour='VCO2'))+
  geom_area(aes(y = (WORK/100)), fill ="lightblue", group=3, alpha = 0.4 ) +
  scale_color_manual(name='Measurement',
                     breaks=c('VO2', 'VCO2', 'VO2', 'WORK'),
                     values=c('VO2'='green', 'VCO2'='red', 'WORK'='blue'))
 p
})

ex_plotlist <- marrangeGrob(ex_plots, nrow=1,ncol=1)
ggsave("multipage.pdf", ex_plotlist, width = 11, height = 8.5, units = "in")

################################################################################
biglist <- mapply(function(x,y,z){list(test_data=x,demo_data=y,changepoints=z)},
            x=test_data,y=demo_data,z=changepoints, SIMPLIFY = F)