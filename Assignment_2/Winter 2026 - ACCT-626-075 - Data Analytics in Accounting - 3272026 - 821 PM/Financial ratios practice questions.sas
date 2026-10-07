/************************************************
SAS practice questions
0.  Set up a library to store your dataset
1.	From Funda dataset, create a new dataset in your temporary WORK library, keep only the company name, year, and data items needed to compute ROA, profit margin and asset turnover. Create these three ratios.
2.	Show the summary statistics of mean, median and std deviation for the ratios that youve created above;
3.	Show the distinct company names in your dataset, how many distinct companies do you have?
4.	Restrict the dataset you created in Step 2 a given industry.
5.	Export the dataset in Step 4 to into CSV format.
6.	Import the dataset that youve exported in the above step into SAS.
7.	Winsorize the outliers (extrem values)
8.	Using proc means, compute the mean ratios of ROA, profit margin and asset turnover for each year. 
9.	Plot the ratios that you�ve created in Step 7.
10.	Using a regression analysis to show the relationship of ROA with profit margin and asset turnover. Are the results as expected?
11.	Create the three ratios in Step 1 using SQL syntax;
**********************/

*There shouldn't be any space in the dataset name;
*SAS Studio: Refer to a path in the Cloud home folder;
*Upload the downloaded file to your Cloud home folder; 
libname A "/homes/hongping.tan@mcgill.ca/MyData";

proc contents data=comp.funda_rev; 	run;

** You may need to modify the codes below to get the right results; 
** Always read the log window for any error messages after you've submitted your SAS codes;

*1.	From Funda dataset, create a new dataset in your temporary WORK library, keep only the company name, year, and data items needed to compute ROA, profit margin and asset turnover.
Create these three ratios.;
data ratio;
	set comp.funda(keep=ni sale at teq epspx prcc_f datadate invt cogs sich conm epspx );
	if sale^=0 then PM=100*ni/sale;
	ROA=100*ni/at;
	ROE=100*ni/teq;
	TAT=sale/at;	*Total asset turnover;
	PE=prcc_f/epspx;
	IT=cogs/invt;
*	EM=at/teq;
	year=year(datadate);
run;

*2.	Show the summary statistics of mean, median and std deviation for the ratios that youve created above;
* Summary statistics;
proc means data=ratio nway n mean median min p1 p5 p10 q1 q3 p99 max std;	
	class year;
	var roa roe tat pe;
	output out=final1 mean=roa_mean roe_mean tat_mean pe_mean median=roa roe tat pe; 
run;	 

*3.	Show the distinct company ID in your dataset, how many distinct companies do you have?;
proc sort data=ratio(keep=gvkey cusip sale sich) nodupkey out=c; by gvkey; 	run; 
proc sort data=ratio(keep=gvkey cusip sale sich) nodupkey out=c; by cusip; 	run; 

*4.	Restrict the dataset you created in Step 2 to a given industry: Hint: SICH as industry variable;
data aa;
	set a.funda(keep=conm);
	where conm like "ENERGY%";
run;

/* In the Cloud Files and Folders pane, navigate to '/home/your-username/' and download your data to your local computer. */
*5.	Export the dataset in Step 4 to your Download folder on your computer into CSV format;
PROC EXPORT DATA=ratio
            OUTFILE= "/home/u45447367/Export/test.csv" 
            DBMS=csv REPLACE;	
run;

*6.	Import the dataset that youve exported in the above step into SAS;
PROC imPORT dataFILE= "/home/u45447367/Export/test.csv"  
	out=a1    
	DBMS=csv REPLACE;	
run;

*7.	Winsorize the outliers (extrem values);
filename m3 url 'https://gist.githubusercontent.com/JoostImpink/497d4852c49d26f164f5/raw/11efba42a13f24f67b5f037e884f4960560a2166/winsorize.sas';
%include m3;
%winsor(dsetin=ratio, dsetout=final, vars=roa pm tat, type=winsor, pctl=1 99);

proc means data=ratio nway mean median min p1 q1 q3 p99 max;	
	var roa pm tat;
run;	 

proc means data=final nway mean median min p1 q1 q3 p99 max;	
	var roa pm tat;
run;	 


*8.	Using proc means, compute the mean ratios of ROA, profit margin and asset turnover for each year;
proc means data=A.test nway mean median;	 
	class year;
	var PM ROA ROE TAT ;
	output out=test1(rename=(_freq_=freq) drop=_type_)  
	median=PM ROA ROE TAt 	median=PM1 ROA1 ROE1 TAT1 ; 
run;	 

proc print data=test1(keep=year roa tat); run;

*9.	Plot the ratios that youve created in Step 7;
PROC SGPLOT DATA = test1;
	SERIES X = year Y = ROA / LEGENDLABEL = 'ROA'
	MARKERS LINEATTRS = (THICKNESS = 2);
	SERIES X = year Y = tat / LEGENDLABEL = 'TAT'
	MARKERS LINEATTRS = (THICKNESS = 2);
	XAXIS TYPE = DISCRETE;
	TITLE 'Financial ratios';
RUN;  *y2axis;


*10. Using a regression analysis to show the relationship of ROA with profit margin and asset turnover. Are the results as expected?;
proc reg data=A.test tableout outest=reg EDF;  
	model roA=pm tat ;
	TITLE 'The determinants';
quit; 

proc surveyreg data=A.test; 
	cluster year; 	*sich;
	model roa = pm tat ; 
quit; 


** If you have worked all the way to here, congratulations!;

*11.	Create the three ratios in Step 1 using SQL syntax;
proc sql;	 	 
	create table compus as select	
	unique conm, year(datadate) as year,       	
	ni/at as roa, 
	ni/SALES as PM, 
	prcc_f/epspx as pe
	from a.FUNDa (keep=gvkey datadate act at sale ni teq dltt cogs invt ceq mkvalt epspx prcc_f tic conm)
	where year(datadate)>=2017 and at>0 and sale>0; 
quit;


**Macros;
/*Impose filter to obtain unique gvkey-datadate records*/
%let compcond=indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C';
 
/*List of Ratios to be calculated*/
%let vars=
 pe_op_basic pe_op_dil pe_exi pe_inc ps pcf evm bm capei dpr npm opmbd opmad gpm ptpm cfm roa roe roce aftret_eq aftret_invcapx aftret_equity pretret_noa pretret_earnat
 equity_invcap  debt_invcap totdebt_invcap int_debt int_totdebt cash_lt invt_act rect_act debt_at short_debt curr_debt lt_debt fcf_ocf adv_sale
 profit_lct debt_ebitda ocf_lct lt_ppent dltt_be debt_assets debt_capital de_ratio intcov cash_ratio quick_ratio curr_ratio capital_ratio cash_debt
 inv_turn  at_turn rect_turn pay_turn sale_invcap sale_equity sale_nwc RD_SALE Accrual GProf be cash_conversion efftax intcov_ratio staff_sale;

%let allvars=&vars divyield ptb bm PEG_trailing PEG_1yrforward PEG_ltgforward;

/*Compustat variables to extract*/
%let avars=
  SEQ ceq TXDITC  TXDB ITCB PSTKRV PSTKL PSTK prcc_f csho epsfx epsfi oprepsx opeps ajex ebit spi nopi
  sale ibadj dvc dvp ib oibdp dp oiadp gp revt cogs pi ibc dpc at ni ibcom icapt mib ebitda xsga
  xido xint mii ppent act lct dltt dlc che invt lt rect xopr oancf txp txt ap xrd xad xlr capx;

/*Define which accounting variables are Year-To-Date, usually from income/cash flow statements*/
%let vars_ytd=sale dp capx cogs xido xint xopr ni pi oibdp oiadp opeps oepsx epsfi epsfx ibadj ibcom mii ibc dpc xrd txt spi nopi;
 

/*Extracting data for Ratios Based on Annual Data and Quarterly Data*/
data temp;
 set a.funda (keep=gvkey datadate fyear fyr datafmt indfmt consol popsrc prcc_f &avars.);
	where &compcond.;
	if at   <=0 then at   =.;
	if sale <=0 then sale =.;
run;


/*WRDS: Calculate annual ratios*/
data A.ratio; 
	set temp;
	by gvkey fyr datadate;
	lagfyear=lag(fyear);
	if first.fyr then lagfyear=.;
	gap=fyear-lagfyear; * year gap between consecutive records;
	pstk_new=coalesce(PSTKRV,PSTKL,PSTK);/*preferred stock*/  *COALESCEC extract the first non-missing value from character variables. COALESCE is for numeric variables;

 	/*Shareholder's Equity, Invested Capital and Operating Cash Flow*/
    if SEQ>0 then BE = sum(SEQ, coalesce(TXDITC,sum(TXDB, ITCB)),-pstk_new);
    if BE<=0 then BE=.;
    if prcc_f*csho>0 then bm = BE/(prcc_f*csho);
    icapt=coalesce(icapt,sum(dltt,pstk,mib,ceq));
    ocf=coalesce(oancf,ib-sum(dif(act),-dif(che),-dif(lct),dif(dlc),dif(txp),-dp));

	/*Annual Valuation Ratios*/
    CAPEI=IB;
    evm=sum(dltt,dlc,mib,pstk_new, prcc_f*csho)/coalesce(ebitda,oibdp,sale-cogs-xsga); /*Enterprise Value Multiple*/
    pe_op_basic=opeps/ajex; /*price-to-operating EPS, excl. EI (basic)*/
    pe_op_dil=oprepsx/ajex; /*price-to-operating EPS, excl. EI (diluted)*/
    pe_exi=epsfx/ajex; /*price-to-earnings, excl. EI (diluted)*/
    pe_inc=epsfi/ajex; /*price-to-earnings, incl. EI (diluted)*/
    ps=sale; /*price-to-sales ratio*/
    pcf=ocf; /*price-to-cash flow*/
    if ibadj>0 then dpr=dvc/ibadj; /*dividend payout ratio*/

	/*Profitability Ratios and Rates of Return*/
    npm=ib/sale;  /*net profit margin*/
    opmbd=coalesce(oibdp,sale-xopr,revt-xopr)/sale;  /*operating profit margin before depreciation*/
    opmad=coalesce(oiadp,oibdp-dp,sale-xopr-dp,revt-xopr-dp)/sale;/*operating profit margin after depreciation*/                                 
    gpm=coalesce(gp,revt-cogs,sale-cogs)/sale; /*gross profit margin*/                                  
    ptpm=coalesce(pi,oiadp-xint+spi+nopi)/sale;  /*pretax profit margin*/                                         
    cfm=coalesce(ibc+dpc,ib+dp)/sale;  /*cash flow margin*/                                    
    roa=coalesce(oibdp,sale-xopr,revt-xopr)/((at+lag(at))/2); /*Return on Assets*/                        
    if ((be+lag(be))/2)>0 then roe=ib/((be+lag(be))/2); /*Return on Equity*/   
    roce=coalesce(ebit,sale-cogs-xsga-dp)/((dltt+lag(dltt)+dlc+lag(dlc)+ceq+lag(ceq))/2); /*Return on Capital Employed*/
    if coalesce(pi,oiadp-xint+spi+nopi)>0 then efftax=txt/coalesce(pi,oiadp-xint+spi+nopi); /*effective tax rate*/
    aftret_eq=coalesce(ibcom,ib-dvp)/((ceq+lag(ceq))/2); /*after tax return on average common equity*/
    if sum(icapt,TXDITC,-mib)>0 then aftret_invcapx=sum(ib+xint,mii)/lag(sum(icapt,TXDITC,-mib)); /*after tax return on invested capital*/
    aftret_equity=ib/((seq+lag(seq))/2); /*after tax return on total stock holder's equity*/
    pretret_noa=coalesce(oiadp,oibdp-dp,sale-xopr-dp,revt-xopr-dp)/((lag(ppent+act-lct)+(ppent+act-lct))/2); /*pretax return on net operating assets*/
    pretret_earnat=coalesce(oiadp,oibdp-dp,sale-xopr-dp,revt-xopr-dp)/((lag(ppent+act)+(ppent+act))/2); /*pretax return on total earning assets*/  
    GProf=coalesce(gp,revt-cogs,sale-cogs)/at;  /*gross profitability as % of total assets*/

	/*Capitalization Ratios*/
    if icapt>0 then
      do;
       equity_invcap=ceq/icapt;   /*Common Equity as % of invested capital*/
       debt_invcap=dltt/icapt;    /*Long-term debt as % of invested capital*/
       totdebt_invcap=(dltt+dlc)/icapt;  /*Total Debt as % of invested capital*/
      end;
     capital_ratio=dltt/(dltt+sum(ceq,pstk_new)); /*capitalization ratio*/

	 /*Financial Soundness Ratios*/
    int_debt=xint/((dltt+lag(dltt))/2); /*interest as % of average long-term debt*/
    int_totdebt=xint/((dltt+lag(dltt)+dlc+lag(dlc))/2); /*interest as % of average total debt*/
    cash_lt=che/lt; /*Cash balance to Total Liabilities*/
    invt_act=invt/act; /*inventory as % of current assets*/
    rect_act=rect/act; /*receivables as % of current assets*/
    debt_at=(dltt+dlc)/at; /*total debt as % of total assets*/
    debt_ebitda=(dltt+dlc)/coalesce(ebitda,oibdp,sale-cogs-xsga); /*gross debt to ebitda*/
    short_debt=dlc/(dltt+dlc); /*short term term as % of total debt*/
    curr_debt=lct/lt; /*current liabilities as % of total liabilities*/
    lt_debt=dltt/lt; /*long-term debt as % of total liabilities*/
    profit_lct=coalesce(OIBDP,sale-xopr)/lct; /*profit before D&A to current liabilities*/
    ocf_lct=ocf/lct; /*operating cash flow to current liabilities*/
    cash_debt=ocf/coalesce(lt,dltt+dlc);/*operating cash flow to total debt*/
    if ocf>0 then fcf_ocf=(ocf-capx)/ocf;  /*Free Cash Flow/Operating Cash Flow*/
    lt_ppent=lt/ppent; /*total liabilities to total tangible assets*/
    if be>0 then dltt_be=dltt/be; /*long-term debt to book equity*/

	/*Solvency Ratios*/
    debt_assets=lt/at; /*Debt-to-assets*/
    debt_capital=(ap+sum(dlc,dltt))/(ap+sum(dlc,dltt)+sum(ceq,pstk_new)); /*debt-to-capital*/
    de_ratio=lt/sum(ceq,pstk_new); /*debt to shareholders' equity ratio*/
    intcov=(xint+ib)/xint; /*after tax interest coverage*/
    intcov_ratio=coalesce(ebit,OIADP,sale-cogs-xsga-dp)/xint; /*interest coverage ratio*/

	/*Liquidity Ratios*/
    if lct>0 then do;
     cash_ratio=che/lct; /*cash ratio*/                                   
     quick_ratio=coalesce(act-invt, che+rect)/lct; /*quick ratio (acid test)*/
     curr_ratio=coalesce(act,che+rect+invt)/LCT; /*current ratio*/
   end;
   cash_conversion=
   ((invt+lag(invt))/2)/(cogs/365)+((rect+lag(rect))/2)/(sale/365)-((ap+lag(ap))/2)/(cogs/365); /*cash conversion cycle*/
    if cash_conversion<0 then cash_conversion=.;

	/*Activity/Efficiency Ratios*/
   if ((invt+lag(invt))/2)>0 then inv_turn=cogs/((invt+lag(invt))/2);  /*inventory turnover*/                    
   if ((at+lag(at))/2)>0 then at_turn=sale/((at+lag(at))/2);   /*asset turnover*/   
   if ((rect+lag(rect))/2)>0 then rect_turn=sale/((rect+lag(rect))/2); /*receivables turnover*/
   if ((ap+lag(ap))/2)>0 then pay_turn=(cogs+dif(invt))/((ap+lag(ap))/2); /*payables turnover*/

	/*Miscallenous Ratios*/
   if icapt>0 then sale_invcap=sale/icapt; /*sale per $ invested capital*/
   if seq>0 then sale_equity=sale/seq; /*sales per $ total stockholders' equity*/
   if act-lct>=0 then sale_nwc=sale/(act-lct);/*sales per $ working capital*/
   rd_sale=sum(xrd,0)/sale; if rd_sale<0 then rd_sale=0; /*R&D as % of sales*/
   adv_sale=sum(xad,0)/sale; /*advertising as % of sales*/
   staff_sale=sum(xlr,0)/sale; /*labor expense as % of sales*/
   accrual = coalesce(ib-oancf,sum(dif(act),-dif(che),-dif(lct),dif(dlc),dif(txp),-dp))/mean(AT,lag(AT));
    
   if first.fyr or gap ne 1 then
   do;
    roa=.;roe=.;roce=.;aftret_eq=.;aftret_invcapx=.;aftret_equity=.;pretret_noa=.;
    pretret_earnat=.;int_debt=.;int_totdebt=.;
    inv_turn=.;at_turn=.;rect_turn=.;cash_conversion=.;
    pay_turn=.;Accrual=.;pcf=.;ocf_lct=.;cash_debt=.;fcf_ocf=.;
   end;

  if at>0;
  rename datadate=adate;
  keep &vars fyear fyr gvkey datadate;
run;
 
proc sort data=A.ratio nodupkey; 	by gvkey adate fyr; 	run;

