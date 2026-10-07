/************************************************
Mini Project 2: Financial Ratios and DuPont Analysis

Student: Louis Zhang

Assignment knowledge points:
SAS: library, date and ratio calculations, proc contents, proc sort,
proc means, Winsorize, proc sgplot
Accounting: financial ratios, DuPont analysis

Directions:
Please incorporate the questions below in your SAS codes as comments.
Please submit both your SAS codes and your answers to the questions
in a Word file. Please copy the graphs and output from SAS and paste
them into the Word file. File names should be your FirstName_LastName.
Please use Funda in the Comp library.
To test your codes, you can set options obs=1000;
Afterwards, change it back to max.
************************************************/

*There shouldn't be any space in the dataset name;
*SAS Studio: Refer to a path in the Cloud home folder;

/* [10 marks] Create a permanent library C with a path referring to a folder
   in your cloud home space; save your final dataset in Step 4 as
   "final_YourNameInitials" to this library. */
libname C "/home/mcgill/louis_zhang";

options obs=max;

/* Check the structure of Comp.Funda */
proc contents data=comp.funda;
run;

/* Load Winsorize macro */
filename m3 url 'https://gist.githubusercontent.com/JoostImpink/497d4852c49d26f164f5/raw/11efba42a13f24f67b5f037e884f4960560a2166/winsorize.sas';
%include m3;

/* [30 marks] From Funda, keep company-level data relevant to calculate
   3-factor DuPont analysis for companies during any 5 years of your choice,
   plus gvkey, two-digit historical SIC codes, market-to-book ratio, and
   other firm characteristics (such as liquidity and solvency) that you
   believe would affect ROE. */

/* Chosen 5-year period: 2018-2022 */

/* Step 1. Create a temporary dataset in WORK library with variables needed
   for ROE, DuPont 3-factor analysis, two-digit SIC, market-to-book ratio,
   and additional firm characteristics. */
data work.ratio_raw;
    set comp.funda(
        keep=gvkey conm datadate fyear indfmt datafmt popsrc consol
             sich ni sale at seq act lct lt prcc_f csho
        where=(fyear between 2018 and 2022)
    );

    /* Standard Compustat annual industrial firm-year filters */
    if indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C';

    /* Keep economically meaningful observations for DuPont analysis */
    if at>0 and sale>0 and seq>0;

    year = fyear;

    /* Two-digit historical SIC code */
    if not missing(sich) and sich>0 then sic2 = floor(sich/100);
    else sic2 = .;

    /* Market value of equity and market-to-book ratio */
    if prcc_f>0 and csho>0 then market_value = prcc_f * csho;
    else market_value = .;

    if seq>0 then mtb = market_value / seq;
    else mtb = .;

    /* DuPont 3-factor analysis */
    pm  = ni / sale;      /* Profit Margin */
    tat = sale / at;      /* Total Asset Turnover */
    em  = at / seq;       /* Equity Multiplier */
    roe = ni / seq;       /* Return on Equity */

    /* Other firm characteristics */
    if lct>0 then cr = act / lct;   /* Current Ratio: liquidity */
    else cr = .;

    if seq>0 then de = lt / seq;    /* Debt-to-Equity: solvency */
    else de = .;

    if at>0 then size = log(at);    /* Firm size */
    else size = .;
run;

/* Sort the dataset */
proc sort data=work.ratio_raw;
    by year gvkey;
run;

/* Show sample size and number of distinct firms */
proc sql;
    select count(*) as firm_year_observations
    from work.ratio_raw;

    select count(distinct gvkey) as distinct_firms
    from work.ratio_raw;
quit;

/* [20 marks] Winsorize your sample at 1 and 99 percent levels,
   and show/explain whether your data is properly winsorized. */

/* Step 2. Show summary statistics before winsorization */
proc means data=work.ratio_raw n mean median min p1 p5 q1 q3 p95 p99 max std;
    var roe pm tat em cr de mtb size;
    title "Summary Statistics Before Winsorization";
run;

/* Step 3. Winsorize the continuous variables at the 1st and 99th percentiles */
%winsor(
    dsetin=work.ratio_raw,
    dsetout=work.ratio_win,
    vars=roe pm tat em cr de mtb size,
    type=winsor,
    pctl=1 99
);

/* Show summary statistics after winsorization */
proc means data=work.ratio_win n mean median min p1 p5 q1 q3 p95 p99 max std;
    var roe pm tat em cr de mtb size;
    title "Summary Statistics After Winsorization";
run;

/* [10 marks] Save your final dataset in Step 4 as "final_YourNameInitials"
   to permanent library C. */

/* Step 4. Save the final winsorized dataset to permanent library C */
data C.final_LZ;
    set work.ratio_win;
run;

/* Compute the mean and median values for ROE and the three components
   of DuPont analysis */
proc means data=C.final_LZ n mean median std;
    var roe pm tat em;
    title "Mean and Median of ROE and DuPont 3 Factors";
run;

/* [30 marks] Plot the DuPont 3 factors over the 5 years.
   What conclusion can you draw? */

/* Step 5. Compute yearly mean and median values for ROE and DuPont factors */
proc means data=C.final_LZ nway mean median;
    class fyear;
    var roe pm tat em;
    output out=yearly_avg(drop=_type_ _freq_)
        mean=roe_mean pm_mean tat_mean em_mean
        median=roe_median pm_median tat_median em_median;
run;

proc print data=yearly_avg;
    title "Yearly Mean and Median Values of ROE and DuPont Components";
run;

/* Step 6. Plot the DuPont 3 factors over the 5-year period */

/* Plot 1: Profit Margin */
proc sgplot data=yearly_avg;
    series x=fyear y=pm_mean / markers lineattrs=(thickness=2);
    xaxis type=discrete label="Fiscal Year";
    yaxis label="Mean Profit Margin";
    title "Trend of Profit Margin (2018-2022)";
run;

/* Plot 2: Total Asset Turnover */
proc sgplot data=yearly_avg;
    series x=fyear y=tat_mean / markers lineattrs=(thickness=2);
    xaxis type=discrete label="Fiscal Year";
    yaxis label="Mean Asset Turnover";
    title "Trend of Asset Turnover (2018-2022)";
run;

/* Plot 3: Equity Multiplier */
proc sgplot data=yearly_avg;
    series x=fyear y=em_mean / markers lineattrs=(thickness=2);
    xaxis type=discrete label="Fiscal Year";
    yaxis label="Mean Equity Multiplier";
    title "Trend of Equity Multiplier (2018-2022)";
run;

/* Optional supporting graph for ROE */
proc sgplot data=yearly_avg;
    series x=fyear y=roe_mean / markers lineattrs=(thickness=2);
    xaxis type=discrete label="Fiscal Year";
    yaxis label="Mean ROE";
    title "Trend of ROE (2018-2022)";
run;

/* Optional regression analysis: ROE on DuPont factors and firm characteristics */
proc reg data=C.final_LZ;
    model roe = pm tat em cr de mtb size;
    title "Regression of ROE on DuPont Factors and Firm Characteristics";
quit;

/* [10 marks] Clarity, readability and professionalism of your graphs/tables. */
/* The tables and graphs above use clear titles, labeled axes, and separate
   plots for each DuPont component to improve readability and professionalism. */