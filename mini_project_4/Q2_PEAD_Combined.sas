/*=============================================================================
  Mini Project 4 – Question 2: PEAD Analysis
  Authors: Ruihe & Zacharie Houle
  Course:  ACCT 626-075, Desautels Faculty of Management, McGill University
  Platform: WRDS SAS Studio

  Structure:
    PART 1 — Broad Market PEAD Replication (2015–2024)
             Macro-level Pre vs Post ChatGPT comparison
    PART 2 — Firm-Level Deep Dive: Salesforce, Inc. (CRM), 2015–2024
             Beat-and-meet, PEAD by tercile, Pre/Post ChatGPT, Fiscal Quarter
    PART 3 — Extension: Salesforce vs SaaS Industry Peers

  IBES-to-CRSP Link Strategy:
    ibes.idsum (oftic) --> crspa.stocknames (ticker) --> PERMNO
    This avoids CUSIP format mismatch between IBES and CRSP
    Deduplicate to one PERMNO per IBES ticker using most recent namedt

  Data Sources:
    - IBES Detail File  (ibes.det_epsus):     Individual analyst forecasts
    - IBES Summary File (ibes.statsum_epsus): Consensus EPS + actuals
    - IBES ID File      (ibes.idsum):         IBES-to-official ticker map
    - CRSP Stocknames   (crspa.stocknames):   Ticker-to-PERMNO map
    - CRSP Daily Stock  (crsp.dsf):           Daily stock returns
    - CRSP Daily S&P500 (crsp.dsp500):        S&P 500 index returns
    - CRSP Daily Index  (crsp.dsi):           VW market index returns
    - Compustat Funda   (comp.funda):         SIC codes for peers
=============================================================================*/

libname ibes  '/wrds/ibes/sasdata';
libname crspa '/wrds/crsp/sasdata/a_stock';

options obs=max;

/*============================================================================
  STEP 0: BUILD IBES-TO-CRSP PERMNO LINK TABLE
  Strategy: ibes.idsum.oftic --> crspa.stocknames.ticker --> PERMNO
  Keep one row per IBES ticker: the most recent PERMNO (max namedt)
============================================================================*/
proc sql;
  create table ibes_crsp_link as
  select a.ticker  as ibes_ticker,
         a.oftic   as official_ticker,
         b.permno,
         b.namedt,
         b.nameenddt
  from ibes.idsum a
  inner join crspa.stocknames b
    on  upcase(a.oftic) = upcase(b.ticker)
  where a.usfirm = 1
    and b.namedt >= '01JAN2000'd   /* Keep modern mappings only */
  order by a.ticker, b.namedt;
quit;

/* Keep most recent PERMNO per IBES ticker */
proc sort data=ibes_crsp_link; by ibes_ticker descending namedt; run;

proc sort data=ibes_crsp_link nodupkey; by ibes_ticker; run;

proc sql;
  select count(*) as N_links, count(distinct ibes_ticker) as N_tickers
  from ibes_crsp_link;
  title 'Step 0: IBES-CRSP link table';
quit; title;

/*============================================================================
  PART 1: BROAD MARKET PEAD REPLICATION (2015–2024)
  - IBES detail file → compute consensus from scratch
  - Link to CRSP via ibes_crsp_link (PERMNO)
  - S&P 500 benchmark (crsp.dsp500, vwretd, caldt)
  - [-30, +90] event window, 5 quintiles, price-scaled SUE
============================================================================*/

/*--- P1 STEP 1: Build consensus from IBES detail file --------------------*/
data ibes_broad_raw;
  set ibes.det_epsus;
  where 2015 <= year(ANNDATS_ACT) <= 2024
    and FPI = '1'
    and VALUE  ne .
    and ACTUAL ne .;
run;

/* Keep latest forecast per analyst per fiscal period */
proc sort data=ibes_broad_raw nodupkey;
  by TICKER FPEDATS ANNDATS_ACT ANALYS descending ANNDATS;
run;

proc sort data=ibes_broad_raw nodupkey;
  by TICKER FPEDATS ANNDATS_ACT ANALYS;
run;

/* Compute consensus = mean analyst forecast per IBES ticker x EAD */
proc means data=ibes_broad_raw nway noprint mean;
  class TICKER ANNDATS_ACT;
  var VALUE;
  id ACTUAL;
  output out=ibes_consensus(keep=TICKER ANNDATS_ACT ACTUAL consensus)
         mean=consensus;
run;

/* Compute surprise and era flags */
data sur_broad;
  set ibes_consensus;
  sur_earn = ACTUAL - consensus;
  if ANNDATS_ACT >= '30NOV2022'd then era = '2_Post_ChatGPT';
  else                                 era = '1_Pre_ChatGPT';
run;

proc sql;
  select count(*) as N_events, count(distinct TICKER) as N_tickers
  from sur_broad;
  title 'P1 Step 1: Broad market events before CRSP merge';
quit; title;

/*--- P1 STEP 2: Beat-and-Meet Histogram ----------------------------------*/
ods graphics on / width=800px height=500px;
proc univariate data=sur_broad noprint;
  where sur_earn between -0.6 and 0.9;
  histogram sur_earn / normal midpoints=-0.6 to 0.9 by 0.1;
  inset n='Number of obs' / position=nw;
  title 'Figure 1: Earnings Surprise Distribution — Broad Market (2015–2024)';
  title2 'Ball & Brown (1968) Beat-and-Meet Replication';
run; title;
ods graphics off;

/*--- P1 STEP 3: Merge IBES with CRSP via PERMNO link --------------------*/
proc sql;
  create table pead_base as
  select i.era,
         i.TICKER as ibes_ticker,
         i.ANNDATS_ACT,
         i.sur_earn,
         j.date,
         j.ret,
         j.prc,
         k.vwretd                    as sp500ret,
         (j.ret - k.vwretd)          as ar,
         (i.sur_earn / abs(j.prc))   as sur_earn_prc,
         intck('weekday', i.ANNDATS_ACT, j.date) as t
  from sur_broad i
  /* Link IBES ticker to PERMNO */
  inner join ibes_crsp_link lnk
    on  i.TICKER = lnk.ibes_ticker
  /* Pull daily returns by PERMNO */
  inner join crsp.dsf j
    on  lnk.permno = j.permno
  /* Pull S&P 500 return */
  inner join crsp.dsp500 k
    on  j.date = k.caldt
  where -30 <= intck('weekday', i.ANNDATS_ACT, j.date) <= 90
    and j.ret    ne .
    and j.prc    ne .
    and k.vwretd ne .
    and abs(j.prc) > 0;
quit;

proc sql;
  select count(*) as N_rows, count(distinct ibes_ticker) as N_firms
  from pead_base;
  title 'P1 Step 3: CRSP panel rows after merge';
quit; title;

/*--- P1 STEP 4: Rank into SUE quintiles within each era -----------------*/
proc sort data=pead_base; by era; run;

proc rank data=pead_base groups=5 ties=low out=pead_ranked;
  by era;
  var sur_earn_prc;
  ranks sur_rank;
run;

/*--- P1 STEP 5: Winsorize AR and SUE at 1/99 ----------------------------*/
proc means data=pead_ranked noprint;
  var ar sur_earn_prc;
  output out=win_pctls p1=ar_p1 sur_p1 p99=ar_p99 sur_p99;
run;

data _null_;
  set win_pctls;
  call symputx('ar_p1',   ar_p1);
  call symputx('ar_p99',  ar_p99);
  call symputx('sur_p1',  sur_p1);
  call symputx('sur_p99', sur_p99);
run;

%put NOTE: AR  P1=&ar_p1  P99=&ar_p99;
%put NOTE: SUE P1=&sur_p1 P99=&sur_p99;

data pead_win;
  set pead_ranked;
  if ar           < &ar_p1   then ar           = &ar_p1;
  if ar           > &ar_p99  then ar           = &ar_p99;
  if sur_earn_prc < &sur_p1  then sur_earn_prc = &sur_p1;
  if sur_earn_prc > &sur_p99 then sur_earn_prc = &sur_p99;
run;

/*--- P1 STEP 6: Compute mean AR by era, quintile, event day -------------*/
proc means data=pead_win nway noprint mean;
  class era sur_rank t;
  var ar;
  output out=pead_mean mean=ar_mean;
run;

proc sort data=pead_mean; by era sur_rank t; run;

/*--- P1 STEP 7: Accumulate CAR ------------------------------------------*/
data pead_cum;
  set pead_mean;
  by era sur_rank t;
  retain cum_car 0;
  if first.sur_rank then cum_car = 0;
  cum_car + ar_mean;
run;

/* Transpose to wide format for plotting */
proc sort data=pead_cum; by era t; run;

proc transpose data=pead_cum
  out=pead_plot(rename=(_0=VeryNeg _1=Negative _2=Neutral
                        _3=Positive _4=VeryPos));
  by era t;
  id sur_rank;
  var cum_car;
run;

/*--- P1 STEP 8: TABLE 1 — CAR summary by quintile and era ---------------*/
proc sql;
  create table pead_summary as
  select era,
    case sur_rank
      when 0 then 'Q1 Most Negative'
      when 1 then 'Q2 Negative'
      when 2 then 'Q3 Neutral'
      when 3 then 'Q4 Positive'
      when 4 then 'Q5 Most Positive'
    end as sue_label,
    mean(case when t between  1 and 30 then cum_car else . end) as CAR_1_30 format=8.4,
    mean(case when t between  1 and 60 then cum_car else . end) as CAR_1_60 format=8.4,
    mean(case when t between  1 and 90 then cum_car else . end) as CAR_1_90 format=8.4,
    count(distinct t) as N_days
  from pead_cum
  group by era, sur_rank
  order by era, sur_rank;
quit;

proc print data=pead_summary noobs label;
  title 'Table 1: PEAD — Broad Market CAR by SUE Quintile and ChatGPT Era';
  label era='Subperiod' sue_label='SUE Quintile'
        CAR_1_30='CAR[+1,+30]' CAR_1_60='CAR[+1,+60]'
        CAR_1_90='CAR[+1,+90]';
run; title;

/*--- P1 STEP 9: FIGURES 2 & 3 — PEAD Line Charts Pre/Post ChatGPT ------*/
ods graphics on / width=900px height=500px;

proc sgplot data=pead_plot;
  where era = '1_Pre_ChatGPT';
  series x=t y=VeryNeg  / legendlabel='Q1 Most Negative'
    lineattrs=(thickness=2 color=CXC00000);
  series x=t y=Negative / legendlabel='Q2 Negative'
    lineattrs=(thickness=2 color=CXFF6600);
  series x=t y=Neutral  / legendlabel='Q3 Neutral'
    lineattrs=(thickness=2 color=CX808080);
  series x=t y=Positive / legendlabel='Q4 Positive'
    lineattrs=(thickness=2 color=CX0070C0);
  series x=t y=VeryPos  / legendlabel='Q5 Most Positive'
    lineattrs=(thickness=2 color=CX00B050);
  refline 0 / axis=x lineattrs=(color=black pattern=dash) label='EAD';
  refline 0 / axis=y lineattrs=(color=gray  pattern=dot);
  xaxis label='Trading Day Relative to EAD' values=(-30 to 90 by 30);
  yaxis label='Cumulative Abnormal Return' valuesformat=percent8.2;
  keylegend / title='SUE Quintile' position=right;
  title  'Figure 2: PEAD — Broad Market, Pre-ChatGPT (Jan 2015–Nov 2022)';
  title2 'Price-Scaled SUE Quintiles | S&P 500 Benchmark';
  footnote 'AR = daily stock return minus S&P 500 return. Winsorized 1/99.';
run;

proc sgplot data=pead_plot;
  where era = '2_Post_ChatGPT';
  series x=t y=VeryNeg  / legendlabel='Q1 Most Negative'
    lineattrs=(thickness=2 color=CXC00000);
  series x=t y=Negative / legendlabel='Q2 Negative'
    lineattrs=(thickness=2 color=CXFF6600);
  series x=t y=Neutral  / legendlabel='Q3 Neutral'
    lineattrs=(thickness=2 color=CX808080);
  series x=t y=Positive / legendlabel='Q4 Positive'
    lineattrs=(thickness=2 color=CX0070C0);
  series x=t y=VeryPos  / legendlabel='Q5 Most Positive'
    lineattrs=(thickness=2 color=CX00B050);
  refline 0 / axis=x lineattrs=(color=black pattern=dash) label='EAD';
  refline 0 / axis=y lineattrs=(color=gray  pattern=dot);
  xaxis label='Trading Day Relative to EAD' values=(-30 to 90 by 30);
  yaxis label='Cumulative Abnormal Return' valuesformat=percent8.2;
  keylegend / title='SUE Quintile' position=right;
  title  'Figure 3: PEAD — Broad Market, Post-ChatGPT (Dec 2022–Dec 2024)';
  title2 'Price-Scaled SUE Quintiles | S&P 500 Benchmark';
  footnote 'AR = daily stock return minus S&P 500 return. Winsorized 1/99.';
run;

ods graphics off; title; footnote;

/*============================================================================
  PART 2: FIRM-LEVEL DEEP DIVE — SALESFORCE, INC. (CRM)
  - IBES summary file, IBES ticker = CRMN, PERMNO = 90215
  - Forecast-scaled SUE, CRSP VW benchmark (crsp.dsi)
  - [-30, +90] event window, 3 terciles, 2015–2024
============================================================================*/

/*--- P2 STEP 1: Pull IBES quarterly data for Salesforce ------------------*/
proc sql;
  create table crm_ibes as
  select ticker, cusip, fpedats,
         ANNDATS_ACT as anndats,
         actual, meanest, medest, numest, fiscalp, fpi
  from ibes.statsum_epsus
  where ticker   = 'CRMN'
  and   fiscalp  = 'QTR'
  and   fpi in ('6','7','8','9')
  and   ANNDATS_ACT between '01JAN2015'd and '31DEC2024'd
  and   actual  ne .
  and   meanest ne .
  order by ANNDATS_ACT;
quit;

proc sort data=crm_ibes nodupkey; by anndats; run;

proc sql;
  select count(*) as N_announcements from crm_ibes;
  title 'P2 Step 1: Salesforce quarterly announcements (expect 40)';
quit; title;

/*--- P2 STEP 2: Compute forecast-scaled SUE and era flags ----------------*/
data crm_sue;
  set crm_ibes;
  if abs(meanest) > 0.01 then sue = (actual - meanest) / abs(meanest);
  else if meanest = 0    then sue = sign(actual - meanest);
  else                        sue = 0;
  if anndats < '30NOV2022'd then chatgpt_era = 'Pre-ChatGPT ';
  else                           chatgpt_era = 'Post-ChatGPT';
  if      fpi = '6' then fiscalq = 'Q1 (Feb-Apr)';
  else if fpi = '7' then fiscalq = 'Q2 (May-Jul)';
  else if fpi = '8' then fiscalq = 'Q3 (Aug-Oct)';
  else if fpi = '9' then fiscalq = 'Q4 (Nov-Jan)';
  else                    fiscalq = 'Other';
  format anndats fpedats date9.;
run;

/*--- P2 STEP 3: Descriptive statistics -----------------------------------*/
proc means data=crm_sue n mean median std min max;
  var sue actual meanest;
  title 'Table 2: SUE Descriptive Statistics — Salesforce (CRM), 2015–2024';
run; title;

proc means data=crm_sue n mean median std;
  class chatgpt_era;
  var sue;
  title 'Table 3: SUE by ChatGPT Era — Salesforce (CRM)';
run; title;

proc means data=crm_sue n mean median std;
  class fiscalq;
  var sue;
  title 'Table 4: SUE by Fiscal Quarter — Salesforce (CRM)';
run; title;

/*--- P2 STEP 4: Beat-and-Meet Histogram ----------------------------------*/
ods graphics on / width=700px height=450px;
proc univariate data=crm_sue noprint;
  histogram sue / normal
    midpoints=-2.0 -1.5 -1.0 -0.5 -0.25 -0.1 -0.05 0
               0.05 0.1 0.25 0.5 1.0 1.5 2.0;
  inset n='N Announcements' mean='Mean SUE' median='Median SUE' / position=ne;
  title 'Figure 4: SUE Distribution — Salesforce (CRM), 2015–2024';
  title2 'Forecast-Scaled Surprise | N=40 Quarterly Announcements';
run; title;
ods graphics off;

/*--- P2 STEP 5: Pull CRSP daily returns for CRM (PERMNO=90215) ----------*/
proc sql;
  create table crm_ret as
  select a.permno, a.date, a.ret, b.vwretd as mkt_ret
  from crsp.dsf a
  left join crsp.dsi b on a.date = b.date
  where a.permno = 90215
    and a.date   between '01JAN2014'd and '31DEC2024'd
    and a.ret    ne .
    and b.vwretd ne .;
quit;

proc sql;
  select count(*) as N_rows,
         min(date) as min_date format=date9.,
         max(date) as max_date format=date9.
  from crm_ret;
  title 'P2 Step 5: CRSP daily returns for CRM';
quit; title;

/*--- P2 STEP 6: Sequential trading day index -----------------------------*/
proc sort data=crm_ret; by date; run;

data crm_ret_tday;
  set crm_ret;
  tday_seq + 1;
run;

/*--- P2 STEP 7: Match EAD to trading day index --------------------------*/
proc sql;
  create table crm_events_tday as
  select e.*, r.tday_seq as edate_tday
  from crm_sue e
  left join crm_ret_tday r on r.date = e.anndats;
quit;

data crm_events_tday;
  set crm_events_tday;
  where edate_tday ne .;
run;

proc sql;
  select count(*) as N_events_matched
  from crm_events_tday;
  title 'P2 Step 7: Events matched to trading days (expect 40)';
quit; title;

/*--- P2 STEP 8: Event window panel [t=-30 to +90] -----------------------*/
proc sql;
  create table crm_panel as
  select e.anndats, e.sue, e.chatgpt_era, e.fiscalq,
         e.actual, e.meanest,
         (r.tday_seq - e.edate_tday) as t,
         r.date, r.ret, r.mkt_ret,
         (r.ret - r.mkt_ret) as ar
  from crm_events_tday e
  inner join crm_ret_tday r
    on (r.tday_seq - e.edate_tday) between -30 and 90;
quit;

proc sort data=crm_panel; by anndats t; run;

/*--- P2 STEP 9: Cumulative abnormal return per event --------------------*/
data crm_car;
  set crm_panel;
  by anndats t;
  retain cum_ar 0;
  if first.anndats then cum_ar = 0;
  cum_ar + ar;
  car = cum_ar;
run;

proc means data=crm_car n mean std min max;
  var car ar;
  title 'Sanity Check: Mean AR should be near 0';
run; title;

/*--- P2 STEP 10: SUE terciles -------------------------------------------*/
proc rank data=crm_car out=crm_car_ranked groups=3;
  var sue;
  ranks sue_tercile_r;
run;

data crm_car_ranked;
  set crm_car_ranked;
  sue_tercile = sue_tercile_r + 1;
  if      sue_tercile = 1 then sue_label = 'T1 Negative Surprise';
  else if sue_tercile = 2 then sue_label = 'T2 Neutral          ';
  else if sue_tercile = 3 then sue_label = 'T3 Positive Surprise';
run;

/*--- P2 STEP 11: TABLE 5 — Main PEAD table ------------------------------*/
proc sql;
  create table pead_main as
  select sue_tercile, sue_label,
    mean(case when t between -30 and -1 then car else . end) as CAR_pre   format=8.4,
    mean(case when t =  0               then car else . end) as CAR_day0  format=8.4,
    mean(case when t between  1 and 30  then car else . end) as CAR_1_30  format=8.4,
    mean(case when t between  1 and 60  then car else . end) as CAR_1_60  format=8.4,
    mean(case when t between  1 and 90  then car else . end) as CAR_1_90  format=8.4,
    count(distinct anndats) as N_events
  from crm_car_ranked
  group by sue_tercile, sue_label
  order by sue_tercile;
quit;

proc print data=pead_main noobs label;
  title 'Table 5: PEAD — CAR by SUE Tercile, Salesforce (CRM), 2015–2024';
  label sue_tercile='Tercile'    sue_label='SUE Group'
        CAR_pre='CAR[-30,-1]'   CAR_day0='CAR[0]'
        CAR_1_30='CAR[+1,+30]' CAR_1_60='CAR[+1,+60]'
        CAR_1_90='CAR[+1,+90]' N_events='N Events';
run; title;

/*--- P2 STEP 12: FIGURE 5 — PEAD Line Chart -----------------------------*/
proc means data=crm_car_ranked nway noprint mean n;
  class sue_tercile sue_label t;
  var car;
  output out=avg_car mean=mean_car;
run;

ods graphics on / width=850px height=500px;
proc sgplot data=avg_car;
  series x=t y=mean_car / group=sue_label lineattrs=(thickness=2.5);
  refline 0 / axis=x lineattrs=(color=black pattern=dash) label='EAD (t=0)';
  refline 0 / axis=y lineattrs=(color=gray  pattern=dot);
  xaxis label='Trading Day Relative to EAD' values=(-30 to 90 by 10);
  yaxis label='Mean CAR (Market-Adjusted)' valuesformat=percent8.2;
  keylegend / title='SUE Tercile' position=bottomright;
  title  'Figure 5: PEAD — Salesforce (CRM), 2015–2024';
  title2 'Cumulative Abnormal Returns by Analyst-Based SUE Tercile';
  footnote 'AR = CRM return minus CRSP VW index return. N=40 events.';
run;
ods graphics off; title; footnote;

/*--- P2 STEP 13: TABLE 6 + FIGURE 6 — Pre vs Post ChatGPT ---------------*/
proc sql;
  create table pead_chatgpt as
  select chatgpt_era, sue_tercile,
    mean(case when t between 1 and 30 then car else . end) as CAR_1_30 format=8.4,
    mean(case when t between 1 and 90 then car else . end) as CAR_1_90 format=8.4,
    count(distinct anndats) as N_events
  from crm_car_ranked
  group by chatgpt_era, sue_tercile
  order by chatgpt_era, sue_tercile;
quit;

proc print data=pead_chatgpt noobs label;
  title 'Table 6: PEAD Before vs After ChatGPT — Salesforce (CRM)';
  label chatgpt_era='Subperiod'  sue_tercile='SUE Tercile'
        CAR_1_30='CAR[+1,+30]'  CAR_1_90='CAR[+1,+90]'
        N_events='N Events';
run; title;

proc means data=crm_car_ranked nway noprint mean;
  class chatgpt_era sue_tercile t;
  var car;
  output out=avg_car_sub mean=mean_car;
run;

data avg_car_sub_plot;
  set avg_car_sub;
  where sue_tercile in (1,3);
  if sue_tercile=1 then sue_grp='T1 Negative Surprise';
  else                  sue_grp='T3 Positive Surprise';
run;

ods graphics on / width=1000px height=500px;
proc sgpanel data=avg_car_sub_plot;
  panelby chatgpt_era / layout=columnlattice novarname columns=2;
  series x=t y=mean_car / group=sue_grp lineattrs=(thickness=2.5);
  refline 0 / axis=x lineattrs=(color=black pattern=dash) label='EAD';
  refline 0 / axis=y lineattrs=(color=gray  pattern=dot);
  rowaxis label='Mean CAR' valuesformat=percent8.2;
  colaxis label='Trading Day Relative to EAD' values=(-30 to 90 by 10);
  keylegend / title='SUE Group';
  title  'Figure 6: PEAD Before vs After ChatGPT — Salesforce (CRM)';
  title2 'T1 (Negative) and T3 (Positive) | Left=Pre, Right=Post ChatGPT';
  footnote 'Pre-ChatGPT: N=31. Post-ChatGPT: N=9.';
run;
ods graphics off; title; footnote;

/*--- P2 STEP 14: TABLE 7 — PEAD by Fiscal Quarter -----------------------*/
proc sql;
  create table pead_fiscalq as
  select fiscalq, sue_tercile,
    mean(case when t between 1 and 30 then car else . end) as CAR_1_30 format=8.4,
    mean(case when t between 1 and 90 then car else . end) as CAR_1_90 format=8.4,
    count(distinct anndats) as N_events
  from crm_car_ranked
  group by fiscalq, sue_tercile
  order by fiscalq, sue_tercile;
quit;

proc print data=pead_fiscalq noobs label;
  title 'Table 7 (Extension): PEAD by Fiscal Quarter — Salesforce (CRM)';
  label fiscalq='Fiscal Quarter' sue_tercile='SUE Tercile'
        CAR_1_30='CAR[+1,+30]'  CAR_1_90='CAR[+1,+90]'
        N_events='N Events';
run; title;

/*============================================================================
  PART 3: EXTENSION — SALESFORCE vs SAAS INDUSTRY PEERS
  - Restrict to SIC 7370-7379 + CRM using Compustat SIC codes
  - Link to CRSP via ibes_crsp_link
  - Q5 (most positive surprise) quintile only
  - Pre vs Post ChatGPT comparison
============================================================================*/

/*--- P3 STEP 1: Identify SaaS peer IBES tickers via CRSP stocknames ----*/
/* Use CRSP stocknames HSICCD (SIC code) to find SaaS peers               */
/* Then link back to IBES via the ibes_crsp_link table we already built    */
proc sql;
  create table saas_permnos as
  select distinct permno
  from crspa.stocknames
  where SICCD between 7370 and 7379
    and nameenddt >= '01JAN2015'd;
quit;

/* Link SaaS PERMNOs back to IBES tickers via ibes_crsp_link */
proc sql;
  create table saas_ibes_tickers as
  select distinct lnk.ibes_ticker
  from saas_permnos s
  inner join ibes_crsp_link lnk
    on s.permno = lnk.permno
  /* Include Salesforce IBES ticker explicitly */
  outer union corr
  select 'CRMN' as ibes_ticker
  from ibes_crsp_link
  where ibes_ticker = 'CRMN';
quit;

proc sql;
  select count(distinct ibes_ticker) as N_saas_tickers
  from saas_ibes_tickers;
  title 'P3 Step 1: SaaS IBES tickers identified';
quit; title;

/*--- P3 STEP 2: Pull SaaS earnings surprises from Part 1 sur_broad ------*/
proc sql;
  create table sur_saas as
  select s.*,
    case when s.TICKER = 'CRMN' then 'Salesforce (CRM)'
         else 'SaaS Peers (SIC 7370-79)'
    end as cohort
  from sur_broad s
  inner join saas_ibes_tickers t
    on s.TICKER = t.ibes_ticker;
quit;

proc sql;
  select cohort, era, count(distinct TICKER) as N_firms,
         count(*) as N_events
  from sur_saas
  group by cohort, era
  order by cohort, era;
  title 'P3 Step 2: SaaS event count by cohort and era';
quit; title;

/*--- P3 STEP 3: Merge SaaS with CRSP ------------------------------------*/
proc sql;
  create table pead_saas_base as
  select i.era,
         i.TICKER as ibes_ticker,
         i.cohort,
         i.ANNDATS_ACT,
         i.sur_earn,
         j.date,
         j.ret,
         j.prc,
         k.vwretd                   as sp500ret,
         (j.ret - k.vwretd)         as ar,
         (i.sur_earn / abs(j.prc))  as sur_earn_prc,
         intck('weekday', i.ANNDATS_ACT, j.date) as t
  from sur_saas i
  inner join ibes_crsp_link lnk
    on  i.TICKER = lnk.ibes_ticker
  inner join crsp.dsf j
    on  lnk.permno = j.permno
  inner join crsp.dsp500 k
    on  j.date = k.caldt
  where -30 <= intck('weekday', i.ANNDATS_ACT, j.date) <= 90
    and j.ret    ne .
    and j.prc    ne .
    and k.vwretd ne .
    and abs(j.prc) > 0;
quit;

/*--- P3 STEP 4: Rank into quintiles within era and cohort ---------------*/
proc sort data=pead_saas_base; by era cohort; run;

proc rank data=pead_saas_base groups=5 ties=low out=peer_ranked;
  by era cohort;
  var sur_earn_prc;
  ranks sur_rank;
run;

/* Keep Q5 — most positive surprise — to trace good-news PEAD */
data good_news_only;
  set peer_ranked;
  where sur_rank = 4;
run;

/*--- P3 STEP 5: Winsorize AR at 1/99 ------------------------------------*/
proc means data=good_news_only noprint;
  var ar;
  output out=peer_wpctls p1=ar_p1 p99=ar_p99;
run;

data _null_;
  set peer_wpctls;
  call symputx('par_p1',  ar_p1);
  call symputx('par_p99', ar_p99);
run;

data peer_win;
  set good_news_only;
  if ar < &par_p1  then ar = &par_p1;
  if ar > &par_p99 then ar = &par_p99;
run;

/*--- P3 STEP 6: Mean AR by era, cohort, event day -----------------------*/
proc means data=peer_win nway noprint mean;
  class era cohort t;
  var ar;
  output out=peer_mean mean=ar_mean;
run;

proc sort data=peer_mean; by era cohort t; run;

/*--- P3 STEP 7: Accumulate CAR ------------------------------------------*/
data peer_cum;
  set peer_mean;
  by era cohort t;
  retain cum_car 0;
  if first.cohort then cum_car = 0;
  cum_car + ar_mean;
run;

/*--- P3 STEP 8: TABLE 8 — CAR comparison --------------------------------*/
proc sql;
  create table peer_summary as
  select era, cohort,
    mean(case when t between 1 and 30 then cum_car else . end) as CAR_1_30 format=8.4,
    mean(case when t between 1 and 60 then cum_car else . end) as CAR_1_60 format=8.4,
    mean(case when t between 1 and 90 then cum_car else . end) as CAR_1_90 format=8.4
  from peer_cum
  group by era, cohort
  order by era, cohort;
quit;

proc print data=peer_summary noobs label;
  title 'Table 8 (Extension): CRM vs SaaS Peers — Q5 Good-News CAR by Era';
  label era='Subperiod' cohort='Firm Group'
        CAR_1_30='CAR[+1,+30]' CAR_1_60='CAR[+1,+60]'
        CAR_1_90='CAR[+1,+90]';
run; title;

/*--- P3 STEP 9: FIGURES 7 & 8 — CRM vs Peers Pre/Post ChatGPT ----------*/
ods graphics on / width=900px height=500px;

proc sgplot data=peer_cum;
  where era = '1_Pre_ChatGPT';
  series x=t y=cum_car / group=cohort lineattrs=(thickness=2.5);
  refline 0 / axis=x lineattrs=(color=black pattern=dash) label='EAD';
  refline 0 / axis=y lineattrs=(color=gray  pattern=dot);
  xaxis label='Trading Day Relative to EAD' values=(-30 to 90 by 30);
  yaxis label='CAR — Q5 Most Positive Surprise' valuesformat=percent8.2;
  keylegend / title='Firm Group' position=topleft;
  title  'Figure 7: CRM vs SaaS Peers — Pre-ChatGPT (Jan 2015–Nov 2022)';
  title2 'Q5 Most Positive SUE | S&P 500 Benchmark';
  footnote 'Higher persistence = more PEAD = less market efficiency.';
run;

proc sgplot data=peer_cum;
  where era = '2_Post_ChatGPT';
  series x=t y=cum_car / group=cohort lineattrs=(thickness=2.5);
  refline 0 / axis=x lineattrs=(color=black pattern=dash) label='EAD';
  refline 0 / axis=y lineattrs=(color=gray  pattern=dot);
  xaxis label='Trading Day Relative to EAD' values=(-30 to 90 by 30);
  yaxis label='CAR — Q5 Most Positive Surprise' valuesformat=percent8.2;
  keylegend / title='Firm Group' position=topleft;
  title  'Figure 8: CRM vs SaaS Peers — Post-ChatGPT (Dec 2022–Dec 2024)';
  title2 'Q5 Most Positive SUE | S&P 500 Benchmark';
  footnote 'Converging lines suggest AI reduced CRM information asymmetry.';
run;

ods graphics off; title; footnote;

/*=== END OF PROGRAM =========================================================*/
