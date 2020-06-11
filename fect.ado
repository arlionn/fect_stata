cap program drop fect
cap program drop cross_validation
cap program drop fect_counter
cap program drop placebo_Test
cap program drop permutation

program define fect,eclass
version 15

syntax varlist(min=1 max=1) [if], Treat(varlist min=1 max=1) ///
								  Unit(varlist min=1 max=1) ///
								  Time(varlist min=1 max=1) ///
								[ cov(varlist) ///
								  force(string) ///
								  degree(integer 3) ///
								  nknots(integer 3) ///
								  r(integer 3) ///
								  lambda(numlist) ///
								  nlambda(integer 10) ///
								  cv ///
								  kfolds(integer 10)  ///
								  cvtreat ///
								  cvnobs(integer 3) ///
								  method(string) ///
								  alpha(real 0.05) ///
								  se ///
								  vartype(string) ///
								  nboots(integer 200) ///
								  tol(real 1e-5) ///
								  maxiterations(integer 5000) ///
								  seed(integer 131210) ///
								  minT0(integer 5) ///
								  maxmissing(integer 0) ///
								  preperiod(integer -999999) ///
								  offperiod(integer 999999) ///
								  wald ///
								  placeboTest ///
								  placeboperiod(integer 3) ///
								  equiTest ///
								  permutation ///
								  Title(string) ///
								  YLABel(string) ///
								  XLABel(string) ///
								  SAVing(string) ///
								  counterfactual ///
								]

set trace off

/*reghdfe*/
cap which reghdfe.ado
if _rc {
	di as error "reghdfe.ado required: {stata ssc install reghdfe,replace}"
	exit 111
}


/* treat */
qui sum `treat'
if(r(min)!=0 | r(max)!=1){
	dis as err "treat() invalid; should only contain 0 and 1."
	exit
}

/* force */
local force = cond("`force'"=="","two-way","`force'")
if ("`force'"!="none" & "`force'"!="unit" & "`force'"!="time" & "`force'"!="two-way") {
	dis as err "force() invalid; choose one from none, unit, time and two-way."
	exit
	}
	
/* degree */
if(`degree'<1) {
	dis as err "degree() must be an integer greater than 1"
    exit
}

/* nknots */
if(`nknots'<3 | `nknots'>7) {
	dis as err "nknots() must be an integer between 3 and 7"
    exit
}

/* r */
if(`r'<1) {
	dis as err "r() must be an integer greater than 1"
    exit
}

/* lambda */
if("`lambda'"!="") {
	local smp = 0
	foreach lambda_grid in `lambda' {
		if(`lambda_grid'<=0){
				dis as err "lambda() invalid; elements in lambda must be positive."
				exit
		}
		local smp=`smp'+1
	}
	if(`smp'==1 & "`cv'"!=""){
		dis as err "lambda() should have at least 2 values when cv is on."
		exit
	}
}


/* nlambda */
if(`nlambda'<1) {
	dis as err "nlambda() must be an integer greater than 1"
    exit
}

/* cv */
if("`cv'"==""){
	local r = `r'
}
else{ 
	local nlambda = `nlambda'
}

/* kfold */
if(`kfolds'<3) {
	dis as err "k() must be an integer greater than 3"
    exit
}
local kfold=`kfolds'

/* cvnobs */							
if(`cvnobs'<1) {
	dis as err "cvnobs() must be an integer greater than 1"
    exit
}

/* method */
local method = cond("`method'"=="","fe","`method'")
if ("`method'"!="fe" & "`method'"!="ife" & "`method'"!="mc" & "`method'"!="bspline" & "`method'"!="polynomial" & "`method'"!="both") {
	dis as err "method() invalid; choose one from fe, ife, mc, bspline, polynomial and both."
	exit
	}

/* alpha */
if(`alpha'>0.5 | `alpha'<0) {
	dis as err "alpha() must be between 0 and 0.5"
    exit
}

/* vartype */
local vartype = cond("`vartype'"=="","bootstrap","`vartype'")
if ("`vartype'"!="bootstrap" & "`vartype'"!="jackknife") {
	dis as err "vartype() invalid; choose one from bootstrap and jackknife."
	exit
	}

/* nboots */
if(`nboots'<10) {
	dis as err "nboots() must be an integer greater than 10."
    exit
}	

/* tol */
if(`tol'<0) {
	dis as err "tol() must be larger than 0"
    exit
}

/* minT0 */
if(`minT0'<1) {
	dis as err "minT0() must be an integer greater than 1"
    exit
}

/* maxmissing */
if(`maxmissing'>0) {
	dis as res "Drop units whose number of missing values is larger than `maxmissing'."
}
if(`maxmissing'<0){
	dis as err "maxmissing() must be an integer greater than 0"
    exit
}

/* preperiod */
if(`preperiod'>0){
	dis as err "preperiod() must be an integer no larger than 0"
    exit
}

if(`offperiod'<0){
	dis as err "offperiod() must be an integer no less than 0"
    exit
}

/* placeboperiod */
if(`placeboperiod'<1) {
	dis as err "placeboperiod() must be an integer not less than 1"
    exit
}

/* saving */
if (strpos("`saving'",".") == 0) {
    local saving = "`saving'.png"
}  

/* EquiTest/PlaceboTest */
if("`se'"==""){
	local equiTest=""
	local placeboTest=""
}

************************************Input Check End

	
/* save raw data */
tempfile raw
qui save `raw',replace
tempvar touse 
mark `touse' `if'
qui drop if `touse'==0

tempvar newid newtime
qui egen `newid'=group(`unit')
sort `newid' `time'
qui egen `newtime'=group(`time')
	   
/* Check if the dataset is strongly balanced */	
qui tsset `newid' `newtime'					   
if "`r(balanced)'"!="strongly balanced"{
	di as res "Unbalanced Panel Data, fill the gap."
	tsfill,full
}
else{
	di as res "Balanced Panel Data"
}							   
sort `newid' `newtime'
qui mata:treat_fill("`treat'","`newid'","`newtime'") //fill the missing values in Treat
tempvar id
/* Check if the dataset is strongly balanced END */

/* Threshold of touse */
tempvar ftreat notreatnum notmissingy missingy
gen `ftreat'=0
qui replace `ftreat'=1 if `treat'==0 & `varlist'!=. //the number of training data
bys `newid':egen `notreatnum'=sum(`ftreat')
qui replace `touse'=0 if `notreatnum'<`minT0'

if(`maxmissing'>0){
bys `newid':egen `notmissingy'=count(`varlist')
qui sum `newtime'
local TT = r(max)-r(min)
qui gen `missingy'=`TT'-`notmissingy'
qui replace `touse'=0 if `missingy'>`maxmissing'
}
qui drop if `touse'==0

if(r(N_drop)!=.){
	di as res "Some treated units has too few pre-treatment periods; they are removed automatically."
}
/* Threshold of touse END*/

/* Cross-Validation */
local lambda_size = wordcount("`lambda'")
local do_cv = 0
if("`method'"=="both"){
	local do_cv = 1
}
if("`cv'"!="" & "`method'"!="fe"){
	local do_cv = 1
}
if((`lambda_size'>1 | `lambda_size'==0)  & "`method'"=="mc"){
	local do_cv = 1
}

if(`do_cv'==1){
	cross_validation `varlist',treat(`treat') unit(`newid') time(`newtime') method(`method') ///
	force(`force') cov(`cov') `cvtreat' cvnobs(`cvnobs') kfold(`kfold') nknots(`nknots') degree(`degree') ///
	r(`r') tol(`tol') maxiterations(`maxiterations') nlambda(`nlambda') lambda(`lambda') seed(`seed')
	
	local method_index=e(method)
	if(`method_index'==0){
		local method="fe"
		local lambda=0
		local r=0
	}
	else if(`method_index'==1){
		local method="ife"
		local r=e(optimal_parameter)
		local lambda=0
	}
	else if(`method_index'==2){
		local method="mc"
		local lambda=e(optimal_parameter)
		local r=0
	}
	else if(`method_index'==3){
		local method="bspline"
		local nknots=e(optimal_parameter)
		local lambda=0
		local r=0
	}
	else if(`method_index'==4){
		local method="polynomial"
		local degree=e(optimal_parameter)
		local lambda=0
		local r=0
	}
	
	local optimal_para=e(optimal_parameter) //to save
	tempname CV
	matrix `CV'=e(CV) //to save
	local min_mspe=e(min_mspe) //to save
}

if("`method'"!="mc"){
	local lambda=0
}

/* Estimate ATT & ATTs */
preserve
tempvar counter TE S ATTs

qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`treat') unit(`newid') time(`newtime')  ///
method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
maxiterations(`maxiterations') lambda(`lambda')

local judge_converge=e(converge)
if `judge_converge'==0{
	dis as err "`method' can't converge"
    exit
}

//coef
tempname coef_output
if("`cov'"!=""){
	mat `coef_output' = e(coef)
	local colnum=colsof(`coef_output')
}
local cons_output = e(cons)


if("`counterfactual'"!=""){
	tempfile counter_out

	cap gen time_relative_to_treatment=`S'
	if _rc!=0 {
		cap replace time_relative_to_treatment=`S'
	}
	cap gen counterfactual_of_response=`counter'
	if _rc!=0 {
		cap replace counterfactual_of_response=`counter'
	}
	qui save `counter_out',replace

	qui drop time_relative_to_treatment
	qui drop counterfactual_of_response
	sort `newid' `newtime'

}

qui sum `S'
local min_s=r(min)
local max_s=r(max)

if(`preperiod'<`min_s'){
	local preperiod=`min_s'
}
else{
	local preperiod=`preperiod'
}

if(`offperiod'>`max_s'){
	local offperiod=`max_s'
}
else{
	local offperiod=`offperiod'
}

sort `newid' `newtime'
qui sum `TE' if `treat'==1 & `touse'==1
local ATT=r(mean) //to save
local N_alltreat=r(N) //to save

tempname sim_nose
tempfile results_nose
qui postfile `sim_nose' s atts s_N using `results_nose',replace

forvalue s=`min_s'/`max_s' {
	qui sum `ATTs' if `S'==`s' & `touse'==1
	if r(N)==0{
		di in red "No observations for s=`s'"
		local s_index=`s'-`min_s'
		local att`s_index' = .
		local N`s_index'=0
	}
	else{
		local s_index=`s'-`min_s'
		local att`s_index' = r(mean)
		local N`s_index'=r(N)
	}
	post `sim_nose' (`s') (`att`s_index'') (`N`s_index'')
}

postclose `sim_nose'

restore

/* Permutation Test */
if("`permutation'"!=""){

permutation `varlist', treat(`treat') unit(`unit') time(`time') ///
cov(`cov') force(`force') degree(`degree') nknots(`nknots') ///
r(`r') lambda(`lambda') method(`method') nboots(`nboots') ///
tol(`tol') maxiterations(`maxiterations') 

local permutation_pvalue=e(permutation_pvalue)
}



/* Bootstrap/Jackknife */
if("`se'"!="" & "`placeboTest'"==""){ 
	tempname sim sim2 sim3
	tempfile results results2 results3
	qui postfile `sim' ATT using `results',replace
	qui postfile `sim2' s ATTs using `results2',replace
	qui postfile `sim3' coef index using `results3',replace
	
	if("`vartype'"=="bootstrap"){
		di as txt "{hline}"	
		di as txt "Bootstrapping..."
		forvalue i=1/`nboots'{
			preserve
			tempvar counter TE S ATTs
			bsample, cluster(`newid') idcluster(boot_id) 
			drop `newid'
			rename boot_id `newid'
			
			capture qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`treat') unit(`newid') time(`newtime')  ///
			method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
			maxiterations(`maxiterations') lambda(`lambda')
			
			if _rc!=0 {
				restore
				continue
			}
			
			/* coefs */
			local cons_output_boot = e(cons)
			post `sim3' (`cons_output_boot') (0)
			tempname coef_output_boot
			if("`cov'"!=""){
				mat `coef_output_boot' = e(coef)
				local colnum=colsof(`coef_output_boot')
				forval ii=1/`colnum'{
					post `sim3' (`coef_output_boot'[1,`ii']) (`ii')
				}
			}
			
			/* ATT */
			qui sum `TE' if `treat'==1 & `touse'==1
			if r(mean)!=.{
				post `sim' (r(mean))
			}

			/* ATTs */
			forvalue si=`min_s'/`max_s' {
				qui sum `ATTs' if `S'==`si' & `touse'==1
				if r(mean)!=.{
					post `sim2' (`si') (r(mean))
				}
			}
			
			if mod(`i',100)==0 {
				di as txt "ATT Estimation: Already Bootstrapped `i' Times"
			}
			restore
		}
		postclose `sim'
		postclose `sim2'
		postclose `sim3'
	}
	
	if("`vartype'"=="jackknife"){
		di as txt "{hline}"	
		di as txt "Jackknifing..."
		tempvar order order_mean order_rank
		bys `newid': gen `order'=runiform()
		bys `newid': egen `order_mean'=mean(`order')
		sort `order_mean'
		egen `order_rank'=group(`order_mean')
		qui sum `newid'
		local max_id=r(max)
		forvalue i=1/`max_id'{
			preserve
			tempvar counter TE S ATTs
			qui drop if `order_rank'==`i'
			
			capture qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`treat') unit(`newid') time(`newtime')  ///
			method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
			maxiterations(`maxiterations') lambda(`lambda')
			
			if _rc!=0 {
				restore
				continue
			}

			/* coefs */
			local cons_output_jack = e(cons)
			post `sim3' (`cons_output_jack') (0)
			tempname coef_output_jack
			if("`cov'"!=""){
				mat `coef_output_jack' = e(coef)
				local colnum=colsof(`coef_output_jack')
				forval ii=1/`colnum'{
					post `sim3' (`coef_output_jack'[1,`ii']) (`ii')
				}
			}
			
			
			/* ATT */
			qui sum `TE' if `treat'==1 & `touse'==1
			if r(mean)!=.{
				post `sim' (r(mean))
			}
		
			/* ATTs */
			forvalue si=`min_s'/`max_s' {
				qui sum `ATTs' if `S'==`si' & `touse'==1
				if r(mean)!=.{
					post `sim2' (`si') (r(mean))
				}
			}
			//di as txt "Jackknife: Round `i' Finished"
			restore
		}
		postclose `sim'
		postclose `sim2'
		postclose `sim3'
	}
	
	
	//get estimation
	
	if("`vartype'"=="bootstrap"){
		//ATT
		preserve
		use `results',clear
		tempname ci ci_att
		qui sum ATT
		local ATTsd=r(sd) //to save
		local twosidel=100*`alpha'/2
		local twosideu=100*(1-`alpha'/2)
		local twoside=100-`alpha'*100
	
		qui _pctile ATT,p(`twosidel' ,`twosideu')
		local ATT_Lower_Bound=r(r1)
		local ATT_Upper_Bound=r(r2)
		matrix `ci_att'=(r(r1),r(r2)) //to save
		matrix rownames `ci_att' = "Confidence Interval" 
		matrix colnames `ci_att' = "Lower Bound" "Upper Bound"
	
		//ATTs
		tempname sim_plot
		tempfile results_plot
		qui postfile `sim_plot' s atts attsd att_lb att_ub s_N using `results_plot',replace
		qui use `results2',clear
		forvalue s=`min_s'/`max_s' {
			qui sum ATTs if s==`s'
			if r(N)<1 {
				continue
			}
			local attsd_temp=r(sd)
			qui _pctile ATTs if s==`s',p(`twosidel' ,`twosideu')
			matrix `ci'=(r(r1),r(r2))
			local s_index=`s'-`min_s'
			if("`vartype'"=="bootstrap"){
				post `sim_plot' (`s') (`att`s_index'') (`attsd_temp') (`ci'[1,1]) (`ci'[1,2]) (`N`s_index'')
			}
		}
		postclose `sim_plot'

		//coef
		tempname sim_coef coef_ci
		tempfile results_coef
		qui postfile `sim_coef' coef sd p_value lower_bound upper_bound using `results_coef',replace
		qui use `results3',clear
		if("`cov'"==""){
			local colnum=0
		}
		forval ii=0/`colnum'{
			if(`ii'>0){
				local coef_tar=`coef_output'[1,`ii']
			}
			if(`ii'==0){
				local coef_tar=`cons_output'
			}
			qui sum coef if index==`ii'
			local coef_sd=r(sd)
			qui _pctile coef if index==`ii',p(`twosidel' ,`twosideu')
			matrix `coef_ci'=(r(r1),r(r2))
			local coef_p=round(2*(1-normal(abs(`coef_tar'/`coef_sd'))),0.001)
			
			post `sim_coef' (`coef_tar') (`coef_sd') (`coef_p') (`coef_ci'[1,1]) (`coef_ci'[1,2])
		}
		postclose `sim_coef'

		restore
	}
	
	
	if("`vartype'"=="jackknife"){
		//ATT
		preserve
		use `results',clear
		tempname ci ci_att
		qui sum ATT
		local ATTsd=r(sd)*sqrt(`max_id') //to save
		
		local tvalue = invttail(`max_id'-1,`alpha'/2)
		local ub_jack = `ATT'+`tvalue'*`ATTsd'
		local lb_jack = `ATT'-`tvalue'*`ATTsd'
		local ATT_Lower_Bound=`lb_jack'
		local ATT_Upper_Bound=`ub_jack'
		matrix `ci_att'=(`lb_jack',`ub_jack') //to save
		matrix rownames `ci_att' = "Confidence Interval" 
		matrix colnames `ci_att' = "Lower Bound" "Upper Bound"
	
		//ATTs
		tempname sim_plot
		tempfile results_plot
		qui postfile `sim_plot' s atts attsd att_lb att_ub s_N using `results_plot',replace
	
		qui use `results2',clear
		forvalue s=`min_s'/`max_s' {
			qui sum ATTs if s==`s'
			if r(N)<1 {
				continue
			}
			local attsd_temp=r(sd)*sqrt(`max_id')
			local s_index=`s'-`min_s'

			if("`vartype'"=="jackknife"){
				local tvalue = invttail(`max_id'-1,`alpha'/2)
				local ub_jack = `att`s_index''+`tvalue'*`attsd_temp'
				local lb_jack = `att`s_index''-`tvalue'*`attsd_temp'
				post `sim_plot' (`s') (`att`s_index'') (`attsd_temp') (`lb_jack') (`ub_jack') (`N`s_index'')
			}
		}
		
		postclose `sim_plot'

		//coef
		tempname sim_coef coef_ci
		tempfile results_coef
		qui postfile `sim_coef' coef sd p_value lower_bound upper_bound using `results_coef',replace
		qui use `results3',clear
		//list
		if("`cov'"==""){
			local colnum=0
		}
		forval ii=0/`colnum'{
			if(`ii'>0){
				local coef_tar=`coef_output'[1,`ii']
			}
			if(`ii'==0){
				local coef_tar=`cons_output'
			}
			qui sum coef if index==`ii'
			local coef_sd=r(sd)*sqrt(`max_id')
			local tvalue = invttail(`max_id'-1,`alpha'/2)
			local ub_jack = `coef_tar'+`tvalue'*`coef_sd'
			local lb_jack = `coef_tar'-`tvalue'*`coef_sd'

			matrix `coef_ci'=(`lb_jack',`ub_jack')
			local coef_p=round(2*(1-normal(abs(`coef_tar'/`coef_sd'))),0.001)
			post `sim_coef' (`coef_tar') (`coef_sd') (`coef_p') (`coef_ci'[1,1]) (`coef_ci'[1,2])
		}
		postclose `sim_coef'

		restore
	}
	
}


if("`se'"=="" & "`placeboTest'"=="" & "`equiTest'"==""){
	tempname sim_plot
	tempfile results_plot
	qui postfile `sim_plot' s atts s_N using `results_plot',replace
	
	forvalue s=`min_s'/`max_s' {
		local s_index=`s'-`min_s'
		post `sim_plot' (`s') (`att`s_index'') (`N`s_index'')
	}
	postclose `sim_plot'
}



/* Wald Test*/
if("`wald'"!=""){
	di as txt "{hline}"	
	di as txt "Wald Testing..."
	tempname sim_wald Fobs
	tempfile results_wald raw2
	qui postfile `sim_wald' SimuF using `results_wald',replace
	qui save `raw2',replace
	
	tempvar counter TE S ATTs
	qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`treat') unit(`newid') time(`newtime')  ///
	method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
	maxiterations(`maxiterations') lambda(`lambda')

	mata:waldF("`newid'", "`newtime'", "`TE'", "`ATTs'", "`S'", `preperiod', 0,"`touse'")
	local F_stat=r(F)
	
	forval i=1/`nboots' {
		preserve
		tempvar counter2 te2 s2 atts2 w new_TE new_outcome
		qui gen `w'=runiformint(0,1)
		qui replace `w'=2*(`w'-0.5)
		qui gen `new_TE'=`w'*`TE'
		qui gen `new_outcome'=`counter'+`new_TE'
		
		qui fect_counter `counter2' `te2' `s2' `atts2',outcome(`new_outcome') treat(`treat') unit(`newid') time(`newtime')  ///
		method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
		maxiterations(`maxiterations') lambda(`lambda')
		
		sort `newid' `newtime'
		mata:waldF("`newid'", "`newtime'", "`te2'", "`atts2'", "`s2'",  `preperiod', 0,"`touse'")
		
		post `sim_wald' (r(F))
		restore	
		if mod(`i',100)==0 {
			di as txt "Wald Testing: Already Simulated `i' Times"
		}	
	}
postclose `sim_wald'

qui use `results_wald',clear
qui sum SimuF
qui count if SimuF>`F_stat'
local larger=r(N)
local WaldF=`F_stat'
local WaldP=`larger'/`nboots' //to save
local waldp_print=string(round(`WaldP',.001))
di as res "The p-value in wald test is `waldp_print'"

qui use `raw2',clear
}


/* Plot */

//draw plot0
if("`se'"=="" & "`placeboTest'"=="" & "`equiTest'"==""){
	preserve
	qui use `results_plot',clear
	qui drop if s<`preperiod'
	qui drop if s>`offperiod'
	qui tsset s

	qui egen max_atts=max(atts)
	qui egen max_N=max(s_N)
	qui sum max_N
	local max_N=r(mean)
	local axis2_up=4*`max_N'
	qui sum max_atts
	local max_atts=1.2*r(mean)
	if `max_atts'<0 {
		local max_atts=0
	}
	qui egen min_atts=min(atts)
	qui sum min_atts
	local min_atts=1.2*r(mean)
	if `min_atts'>0 {
		local min_atts=0
	}

	if(abs(`max_atts')>abs(`min_atts')){
		local min_atts=-`max_atts'*0.8
	}
	else{
		local max_atts=-`min_atts'*0.8
	}
	
	/* Title */
	local xlabel = cond("`xlabel'"=="","Time relative to the Treatment","`xlabel'")
	local ylabel = cond("`ylabel'"=="","Average Treatment Effect","`ylabel'")
	local title = cond("`title'"=="","Estimated Average Treatment Effect","`title'") 
	if("`wald'"!=""){
		local note = "Wald p-value: `waldp_print'"
	}
	else{
		local note = " "
	}
	
	qui gen y0=0
	twoway (line atts y0 s,lcolor(blue gray) yaxis(1) lpattern(solid) lwidth(1.1)) ///
	(bar s_N s,yaxis(2) barwidth(0.5) color(midblue%50)), ///
	 xline(0, lcolor(midblue) lpattern(dash)) ///
	 yscale(axis(2) r(0 `axis2_up')) ///
	 yscale(axis(1) r(`min_atts' `max_atts')) ///
	 xlabel(`preperiod' 0 `offperiod') ///
	 xtick(`preperiod'(1)`offperiod') ///
	 ylabel(0 `max_N',axis(2)) ///
	 ytitle(`ylabel',axis(1)) ///
	 ytitle("Num of observations",axis(2)) ///
	 xtitle(`xlabel') ///
	 title(`title') ///
	 text(`max_atts' `preperiod' "`note'",place(e)) ///
	 scheme(s2mono) ///
	 graphr(fcolor(ltbluishgray8)) ///
	 legend(order( 1 "ATT")) 
	 
	if("`saving'"!=""){
       cap graph export `saving',replace
	} 
	restore
}


//draw plot1
if("`se'"!="" & "`placeboTest'"=="" & "`equiTest'"==""){
	preserve
	qui use `results_plot',clear
	qui drop if s<`preperiod'
	qui drop if s>`offperiod'
	qui tsset s
	local CIlevel=100*(1-`alpha')
	qui egen max_atts=max(att_ub)
	qui egen max_N=max(s_N)
	qui sum max_N
	local max_N=r(mean)
	local axis2_up=4*`max_N'
	qui sum max_atts
	local max_atts=1.2*r(mean)
	if `max_atts'<0 {
	local max_atts=0
	}
	qui egen min_atts=min(att_lb)
	qui sum min_atts
	local min_atts=1.2*r(mean)
	if `min_atts'>0 {
		local min_atts=0
	}

	if(abs(`max_atts')>abs(`min_atts')){
		local min_atts=-`max_atts'*0.8
	}
	else{
		local max_atts=-`min_atts'*0.8
	}
	
	/* Title */
	local xlabel = cond("`xlabel'"=="","Time relative to the Treatment","`xlabel'")
	local ylabel = cond("`ylabel'"=="","Average Treatment Effect","`ylabel'")
	local title = cond("`title'"=="","Estimated Average Treatment Effect","`title'") 
	if("`wald'"!=""){
		local note = "Wald p-value: `waldp_print'"
	}
	else{
		local note = " "
	}
	
	qui gen y0=0
	twoway (rarea att_lb att_ub s, color(gray%30) lcolor(gray) yaxis(1)) ///
	(line atts y0 s,lcolor(black gray) yaxis(1) lpattern(solid) lwidth(1.1)) ///
	(bar s_N s,yaxis(2) barwidth(0.5) color(midblue%50)), ///
	 xline(0, lcolor(midblue) lpattern(dash)) ///
	 yscale(axis(2) r(0 `axis2_up')) ///
	 yscale(axis(1) r(`min_atts' `max_atts')) ///
	 xlabel(`preperiod' 0 `offperiod') ///
	 xtick(`preperiod'(1)`offperiod') ///
	 ylabel(0 `max_N',axis(2)) ///
	 ytitle(`ylabel',axis(1)) ///
	 ytitle("Num of observations",axis(2)) ///
	 xtitle(`xlabel') ///
	 title(`title') ///
	 text(`max_atts' `preperiod' "`note'",place(e)) ///
	 scheme(s2mono) ///
	 graphr(fcolor(ltbluishgray8)) ///
	 legend(order( 1 "ATT `CIlevel'% CI" 2 "ATT")) 
	 
	if("`saving'"!=""){
       cap graph export `saving',replace
	} 
	restore
}


/* Equivalence Test */
//draw plot2
if("`se'"!="" & "`placeboTest'"=="" & "`equiTest'"!=""){
	di as txt "{hline}"	
	di as txt "Equivalence Test"
	qui reg `varlist' `cov' i.`newid' i.`newtime' if `treat'==0 & `touse'==1							   
	local ebound= 0.36*e(rmse)
	
	/* Etest is an one-side test*/
	local twosidel=100*`alpha'
	local twosideu=100*(1-`alpha')
	local twoside=100-`alpha'*100
	
	preserve
	tempname sim_etest
	tempfile results_etest
	qui postfile `sim_etest' s atts att_lb att_ub s_N using `results_etest',replace
	
	qui use `results2',clear
	local et_flag=0
	forvalue s=`min_s'/`max_s' {
		qui sum ATTs if s==`s'
		if r(N)<1 {
			continue
		}
	
		qui _pctile ATTs if s==`s',p(`twosidel' ,`twosideu')
		matrix `ci'=(r(r1),r(r2))
		local s_index=`s'-`min_s'
		post `sim_etest' (`s') (`att`s_index'') (`ci'[1,1]) (`ci'[1,2]) (`N`s_index'')
		
		if (`ci'[1,1]<(-`ebound') | `ci'[1,2]>(`ebound'))&(`s'<=0 & `s'>=`preperiod') { 
			di as res "Equivalence Test...Fail at s=`s'"
			local et_flag=1
		}
	}
	if(`et_flag'==1){
		di as res "Equivalence Test...Fail"
	}
	else{
		di as res "Equivalence Test...Pass"
	}
	postclose `sim_etest'
	
	/* Draw Plot */
	qui use `results_etest',clear
	qui drop if s<`preperiod'
	qui drop if s>`offperiod'
	qui tsset s
	qui egen max_atts=max(att_ub) if s<=0
	qui sum max_atts
	qui gen yub=r(mean)
	local max_atts=2*r(mean)
	if `max_atts'<0 {
		local max_atts=0
	}
	if `max_atts'<`ebound' {
		local max_atts=`ebound'*2
	}
	qui egen min_atts=min(att_lb) if s<=0
	qui sum min_atts
	qui gen ylb=r(mean)
	local min_atts=2*r(mean)
	if `min_atts'>0 {
		local min_atts=0
	}
	if `min_atts'>-`ebound' {
		local min_atts=-`ebound'*2
	}
	qui egen max_N=max(s_N)
	qui sum max_N
	local max_N=r(mean)
	local axis2_up=8*`max_N'
	local CIlevel=100*(1-`alpha')
	local Tlevel=100*(1-2*`alpha')
	qui gen y0=0
	qui gen y1=`ebound'
	qui gen y2=-`ebound'

	if(abs(`max_atts')>abs(`min_atts')){
		local min_atts=-`max_atts'*0.8
	}
	else{
		local max_atts=-`min_atts'*0.8
	}

	
	/* Title */
	local xlabel = cond("`xlabel'"=="","Time relative to the Treatment","`xlabel'")
	local ylabel = cond("`ylabel'"=="","Average Treatment Effect","`ylabel'")
	local title = cond("`title'"=="","Equivalence Test","`title'")
	
	twoway (rarea att_lb att_ub s, color(gray%30)  lcolor(gray) yaxis(1)) ///
	(line atts y0 s,lcolor(black gray) lpattern(solid) yaxis(1) lwidth(1.1)) ///
	(line y1 y2 ylb yub s if s<=0,lcolor(blue blue green green) lpattern(dash dash dash dash) yaxis(1) lwidth(0.5 0.5 0.5 0.5)) ///
	(bar s_N s,yaxis(2) barwidth(0.5) color(midblue%50)), ///
	xline(0, lcolor(midblue) lpattern(dash)) ///
	ysc(axis(1) r(`min_atts' `max_atts')) ///
	ysc(axis(2) r(0 `axis2_up')) ///
	ylabel(0 `max_N',axis(2)) ///
	xlabel(`preperiod' 0 `offperiod') ///
	xtick(`preperiod'(1)`offperiod') ///
	ytitle(`ylabel',axis(1)) ///
	ytitle("Num of Observations",axis(2)) ///
	xtitle(`xlabel') ///
	title(`title') ///
	scheme(s2mono) ///
	graphr(fcolor(ltbluishgray8)) ///
	legend(order(1 "ATT(`Tlevel'% CI)"  2 "ATT" 4 "Equiv.Bound" 6 "Min.Bound")) 
	
	if("`saving'"!=""){
       cap graph export `saving',replace
	} 
	restore

}

/* Placebo Test */
//draw plot3
if("`placeboTest'"!="" & "`se'"!="" & "`equiTest'"==""){

	placebo_Test `varlist',treat(`treat') unit(`newid') time(`newtime') cov(`cov') method("`method'") ///
	force("`force'") degree(`degree') nknots(`nknots') r(`r') lambda(`lambda') alpha(`alpha') vartype("`vartype'") ///
	nboots(`nboots') tol(`tol') maxiterations(`maxiterations') seed(`seed') minT0(`minT0') maxmissing(`maxmissing') ///
	preperiod(`preperiod') offperiod(`offperiod') placeboperiod(`placeboperiod') xlabel(`xlabel') ylabel(`ylabel') title(`title') saving(`saving')
	
	//to save
	local placebo_pvalue=e(placebo_pvalue)
	local placebo_ATT_mean=e(placebo_ATT_mean)
	local placebo_ATT_sd=e(placebo_ATT_sd)
	tempname placebo_CI
	matrix `placebo_CI' = e(placebo_CI)
	
}




/* Storage */
ereturn clear
//CV
if( `do_cv'==1){
	ereturn scalar optimal_parameter=`optimal_para'
	ereturn scalar min_mspe=`min_mspe'
	ereturn matrix CV=`CV'
}
//ATT
ereturn scalar ATT=`ATT'
ereturn scalar n=`N_alltreat'

if("`se'"==""){
	preserve
	qui use `results_nose',clear
	qui rename atts ATT
	qui rename s_N n
	order s n ATT
	tempname ATTs_matrix
	qui mkmat s n ATT, matrix(`ATTs_matrix')
	ereturn matrix ATTs=`ATTs_matrix'
	if("`cov'"!=""){
		ereturn matrix coefs=`coef_output'
	}
	ereturn scalar mu=`cons_output'

	restore
}

//ATTsd
if("`se'"!="" & "`placeboTest'"==""){
	ereturn scalar ATTsd=`ATTsd'
	ereturn matrix ATTCI=`ci_att'

	ereturn scalar ATT_Lower_Bound=`ATT_Lower_Bound'
	ereturn scalar ATT_Upper_Bound=`ATT_Upper_Bound'
	ereturn scalar ATT_pvalue=round(2*(1-normal(abs(`ATT'/`ATTsd'))),0.001)
}

//ATTs & coef
if("`se'"!="" & "`placeboTest'"==""){
	preserve
	qui use `results_plot',clear
	qui rename atts ATT
	qui rename attsd ATT_sd
	qui rename att_lb ATT_Lower_Bound
	qui rename att_ub ATT_Upper_Bound
	qui rename s_N n
	
	gen ATT_p_value=2*(1-normal(abs(ATT/ATT_sd)))
	
	order s n ATT ATT_sd ATT_p_value ATT_Lower_Bound ATT_Upper_Bound
	tempname ATTs_matrix
	qui mkmat s n ATT ATT_sd ATT_p_value ATT_Lower_Bound ATT_Upper_Bound, matrix(`ATTs_matrix')
	ereturn matrix ATTs=`ATTs_matrix'

	qui use `results_coef',clear
	tempname coefs_matrix_output
	qui mkmat coef sd p_value lower_bound upper_bound, matrix(`coefs_matrix_output')
	matrix rownames  `coefs_matrix_output'= cons `cov'
	ereturn matrix coefs=`coefs_matrix_output'

	restore
}
//permutation
if("`permutation'"!=""){
	ereturn scalar permutation_pvalue=`permutation_pvalue'
}

//Wald
if("`wald'"!=""){
	ereturn scalar wald_pvalue=`WaldP'
}

//Placebo
if("`placeboTest'"!=""){
	ereturn scalar placebo_pvalue=`placebo_pvalue'
	ereturn scalar placebo_ATT=`placebo_ATT_mean'
	ereturn scalar placebo_ATT_sd=`placebo_ATT_sd'
	ereturn matrix placebo_ATT_CI=`placebo_CI'
}

//counterfactual
qui use `raw',clear	
if("`counterfactual'"!=""){
	//di as res "Counterfactual"
	qui use `counter_out',clear
	
}


		   
end

*********************************************************functions
program fect_counter,eclass
syntax newvarlist(min=4 max=4 gen) [if] , outcome(varlist min=1 max=1) ///
									treat(varlist min=1 max=1) ///
									unit(varlist min=1 max=1) ///
									time(varlist min=1 max=1) ///
									method(string) ///
									force(string) ///
									[ cov(varlist) ///
									  nknots(integer 3) ///
									  degree(integer 3) ///
									  r(integer 2) ///
									  tol(real 1e-5) ///
									  maxiterations(integer 5000) ///
									  lambda(real 0.5) ///
									]

set trace off
tempvar touse 
mark `touse' `if'

tempvar newid newtime
qui egen `newid'=group(`unit')
sort `newid' `time'
qui egen `newtime'=group(`time')

/* Normalization */
tempvar norm_y
//qui sum `outcome' if `treat'==0 & `touse'==1
//local mean_y=r(mean)
//local sd_y=r(sd)
//qui gen `norm_y'=(`outcome'-`mean_y')/`sd_y'
qui gen `norm_y'=`outcome'

/* Regression/Training */

if("`method'"=="fe"){
	tempvar FE1 FE2 yearFE unitFE counterfactual
	if("`force'"=="two-way"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid' `FE2'=`newtime') savefe
	}
	if("`force'"=="unit"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid') savefe
		qui gen `FE2'=0
	}
	if("`force'"=="time"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE2'=`newtime') savefe
		qui gen `FE1'=0
	}
	if("`force'"=="none"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,noabsorb
		qui gen `FE2'=0
		qui gen `FE1'=0
	}

	qui bys `newtime':egen `yearFE'=mean(`FE2')
	qui bys `newid':egen `unitFE'=mean(`FE1')
	drop `FE1' `FE2'
	qui gen double `counterfactual'=_b[_cons]+`unitFE'+`yearFE' 
	if "`cov'"!="" {
		tempname coefficient
		matrix `coefficient'=e(b)
		local colnum=colsof(`coefficient')-1
		forval i=1/`colnum'{
			local p=word("`cov'",`i')
			qui replace `counterfactual'=`counterfactual'+`p'*`coefficient'[1,`i']
		}
	}
	local Converge=1
	tempname coef_output
	if( "`cov'"!=""){
		forval i=1/`colnum'{
			if(`i'==1){
				matrix `coef_output'=(`coefficient'[1,`i'])
			}
			else{
				matrix `coef_output'=(`coef_output',`coefficient'[1,`i'])
			}
		}
	}
	local mu_output=_b[_cons]
}

if("`method'"=="bspline"){
	tempvar trend
	tempvar FE1 FE2 yearFE unitFE counterfactual FE
	qui mkspline `trend' = `newtime',cubic nknots(`nknots')
	local run = `nknots'-1
	forvalue i=1/`run'{
		local trend_all `trend_all' `trend'`i'
		tempvar `FE'Slope`i'
	}
	
	if("`force'"=="two-way"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid' `FE2'=`newtime' `FE'=i.`newid'#c.(`trend_all')) savefe
	}
	if("`force'"=="unit"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid' `FE'=i.`newid'#c.(`trend_all')) savefe
		qui gen `FE2'=0
	}
	if("`force'"=="time"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE2'=`newtime' `FE'=i.`newid'#c.(`trend_all')) savefe
		qui gen `FE1'=0
	}
	if("`force'"=="none"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE'=i.`newid'#c.(`trend_all')) savefe
		qui gen `FE2'=0
		qui gen `FE1'=0
	}
	
	qui bys `newtime':egen `yearFE'=mean(`FE2')
	qui bys `newid':egen `unitFE'=mean(`FE1')
	drop `FE1' `FE2'
	
	if("`force'"!="none"){
		qui gen `counterfactual'=_b[_cons]+`unitFE'+`yearFE' 
	}
	else{
		qui gen `counterfactual'=0
	}
	
	
	if "`cov'"!="" {
		tempname coefficient
		matrix `coefficient'=e(b)
		if("`force'"!="none"){
			local colnum=colsof(`coefficient')-1
		}
		else{
			local colnum=colsof(`coefficient')
		}
		forval i=1/`colnum'{
			local p=word("`cov'",`i')
			qui replace `counterfactual'=`counterfactual'+`p'*`coefficient'[1,`i']
		}
	}
	
	forvalue i=1/`run'{
		qui bys `newid':egen `unitFE'`i'=mean(`FE'Slope`i')
		qui replace `counterfactual'=`counterfactual'+`unitFE'`i'*`trend'`i'
	}
	local Converge=1
	tempname coef_output
	if( "`cov'"!=""){
		forval i=1/`colnum'{
			if(`i'==1){
				matrix `coef_output'=(`coefficient'[1,`i'])
			}
			else{
				matrix `coef_output'=(`coef_output',`coefficient'[1,`i'])
			}
		}
	}
	local mu_output=_b[_cons]
}

if("`method'"=="polynomial"){
	tempvar trend
	tempvar FE1 FE2 yearFE unitFE counterfactual FE
	forvalue i=1/`degree'{
		qui gen `trend'`i' = `newtime'^`i'
		local trend_all `trend_all' `trend'`i'
	}
	
	
	if("`force'"=="two-way"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid' `FE2'=`newtime' `FE'=i.`newid'#c.(`trend_all')) savefe
	}
	if("`force'"=="unit"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid' `FE'=i.`newid'#c.(`trend_all')) savefe
		qui gen `FE2'=0
	}
	if("`force'"=="time"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE2'=`newtime' `FE'=i.`newid'#c.(`trend_all')) savefe
		qui gen `FE1'=0
	}
	if("`force'"=="none"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE'=i.`newid'#c.(`trend_all')) savefe
		qui gen `FE2'=0
		qui gen `FE1'=0
	}
	
	qui bys `newtime':egen `yearFE'=mean(`FE2')
	qui bys `newid':egen `unitFE'=mean(`FE1')
	drop `FE1' `FE2'
	
	if("`force'"!="none"){
		qui gen `counterfactual'=_b[_cons]+`unitFE'+`yearFE' 
	}
	else{
		qui gen `counterfactual'=0
	}
	
	if "`cov'"!="" {
		tempname coefficient
		matrix `coefficient'=e(b)
		if("`force'"!="none"){
			local colnum=colsof(`coefficient')-1
		}
		else{
			local colnum=colsof(`coefficient')
		}
		forval i=1/`colnum'{
			local p=word("`cov'",`i')
			qui replace `counterfactual'=`counterfactual'+`p'*`coefficient'[1,`i']
		}
	}
	
	forvalue i=1/`degree'{
		qui bys `newid':egen `unitFE'`i'=mean(`FE'Slope`i')
		qui replace `counterfactual'=`counterfactual'+`unitFE'`i'*`trend'`i'
	}
	local Converge=1
	tempname coef_output
	if( "`cov'"!=""){
		forval i=1/`colnum'{
			if(`i'==1){
				matrix `coef_output'=(`coefficient'[1,`i'])
			}
			else{
				matrix `coef_output'=(`coef_output',`coefficient'[1,`i'])
			}
		}
	}
	local mu_output=_b[_cons]
}

if("`method'"=="ife"){
	tempvar FE1 FE2 yearFE unitFE cons counterfactual p_treat
	if("`force'"=="two-way"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid' `FE2'=`newtime') savefe
	}
	if("`force'"=="unit"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid') savefe
		qui gen `FE2'=0
	}
	if("`force'"=="time"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,absorb(`FE2'=`newtime') savefe
		qui gen `FE1'=0
	}
	if("`force'"=="none"){
		qui reghdfe `norm_y' `cov' if `treat'==0 & `touse'==1,noabsorb
		qui gen `FE2'=0
		qui gen `FE1'=0
	}
	qui gen `cons'=_b[_cons]
	qui bys `newtime':egen `yearFE'=mean(`FE2')
	qui bys `newid':egen `unitFE'=mean(`FE1')
	drop `FE1' `FE2'
	
	sort `newid' `newtime'
	qui gen `p_treat'=0 
	qui replace `p_treat'=1 if `treat'==1 | `touse'==0 | `norm_y'==.
	qui mata: ife("`norm_y'","`cov'","`p_treat'","`newid'","`newtime'","`force'",`r',`tol',`maxiterations',"`counterfactual'","`unitFE'","`yearFE'","`cons'")
	if(r(stop)==1){
		local Converge=1
	}
	else{
		local Converge=0
		di as res "IFE can't converge."
	}
	tempname coef_output
	if "`cov'"!=""{
		matrix `coef_output'=r(coef)
	}
	local mu_output=r(cons)

}

if("`method'"=="mc"){
	tempvar y FE1 FE2 yearFE unitFE cons counterfactual p_treat
	qui gen `y'=`outcome'
	if("`force'"=="two-way"){
		qui reghdfe `y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid' `FE2'=`newtime') savefe
	}
	if("`force'"=="unit"){
		qui reghdfe `y' `cov' if `treat'==0 & `touse'==1,absorb(`FE1'=`newid') savefe
		qui gen `FE2'=0
	}
	if("`force'"=="time"){
		qui reghdfe `y' `cov' if `treat'==0 & `touse'==1,absorb(`FE2'=`newtime') savefe
		qui gen `FE1'=0
	}
	if("`force'"=="none"){
		qui reghdfe `y' `cov' if `treat'==0 & `touse'==1,noabsorb
		qui gen `FE2'=0
		qui gen `FE1'=0
	}
	qui gen `cons'=_b[_cons]
	qui bys `newtime':egen `yearFE'=mean(`FE2')
	qui bys `newid':egen `unitFE'=mean(`FE1')
	drop `FE1' `FE2'
	
	sort `newid' `newtime'
	qui gen `p_treat'=0 
	qui replace `p_treat'=1 if `treat'==1 | `touse'==0 | `y'==.
	qui mata: mc("`y'","`cov'","`p_treat'","`newid'","`newtime'","`force'",`lambda',`tol',`maxiterations',"`counterfactual'","`unitFE'","`yearFE'","`cons'")
	if(r(stop)==1){
		local Converge=1
	}
	else{
		local Converge=0
		di as res "MC can't converge."
	}
	
	tempname coef_output
	if "`cov'"!=""{
		matrix `coef_output'=r(coef)
	}
	local mu_output=r(cons)
}

if("`cov'"!=""){
	matrix colnames `coef_output' = `cov'
}

token `varlist'
qui replace `1' = `counterfactual'

tempvar treat_effect
qui gen double `treat_effect'=`outcome'-`counterfactual' 
qui replace `2' = `treat_effect'
sort `unit' `time'

tempvar treatsum targettime target ATTs
qui mata:gen_s("`treat'","`newid'","`newtime'","`target'")
qui bys `target':egen `ATTs'= mean(`treat_effect') if `target'!=. & `touse'==1
qui replace `3' = `target' if `touse'==1 
qui replace `4' = `ATTs' if `touse'==1
qui sort `newid' `newtime'
ereturn scalar converge=`Converge'
ereturn scalar cons= `mu_output'
if("`cov'"!=""){
	ereturn matrix coef= `coef_output'
}

end

program cross_validation,eclass
syntax varlist(min=1 max=1), treat(varlist min=1 max=1) ///
						     unit(varlist min=1 max=1) ///
						     time(varlist min=1 max=1) ///
						     method(string) ///
							 force(string) ///
							[ cov(varlist) ///
							  cvtreat ///
							  cvnobs(integer 3) ///
							  kfold(integer 10) ///
							  nknots(integer 3) ///
							  degree(integer 3) ///
							  r(integer 3) ///
							  tol(real 1e-4) ///
							  maxiterations(integer 5000) ///
							  nlambda(integer 10) ///
							  lambda(numlist ascending) ///
							  seed(integer 123) ///
						    ]

set trace off
di as txt "{hline}"	
di as txt "Cross Validation..."
tempvar newid newtime touse
qui gen `touse'=1
qui egen `newid'=group(`unit')
qui egen `newtime'=group(`time')
sort `newid' `newtime'

tempvar validation
tempname sim final_sim final_sim2
tempfile results final_results final_results2	

gen `validation'=0
sort `newid' `time'
mata: val_gen("`treat'", "`newid'", "`newtime'", "`touse'", ///
`kfold',`cvnobs',"`validation'",`seed')

/* Only for treated values */
if("`cvtreat'"!=""){ 
	tempvar iftreat
	qui bys `newid': egen `iftreat'=mean(`treat')
	qui replace `validation'=0 if `iftreat'==0
}

if("`method'"=="ife" | "`method'"=="both"){
	qui postfile `final_sim' r mspe using `final_results',replace
	forval fnum=0/`r' {
		//di as res "Factor: `fnum'"
		qui postfile `sim' N spe using `results',replace
		if `fnum'==0 {
			forval i=1/`kfold' {
				preserve
				tempvar counter spe TE S ATTs
				qui fect_counter `counter' `TE' `S' `ATTs' if `validation'!=`i' & `touse'==1,outcome(`varlist') ///
				treat(`treat') unit(`newid') time(`newtime') ///
				cov(`cov') method("fe") force("`force'") 
				
				if(e(converge)==0){
					restore
					continue
				}

				qui gen `spe'=(`varlist'-`counter')^2 if `validation'==`i' & `touse'==1
				qui sum `spe' if `validation'==`i' & `touse'==1
				if r(N)!=0 {
					post `sim' (r(N)) (r(mean))
				}
				restore
			}
		postclose `sim'

		preserve
		use `results',clear
		tempvar weight_mean
		egen `weight_mean'=wtmean(spe),weight(N)
		qui sum `weight_mean'
		post `final_sim' (0) (r(mean))
		local mspe = string(round(r(mean),.001))
		di as txt "fe r=0 force=`force' mspe=`mspe'"
		restore
		continue
		}

		/* ife */
		forval i=1/`kfold' {
			preserve
			tempvar counter spe TE S ATTs

			qui fect_counter `counter' `TE' `S' `ATTs' if `validation'!=`i' & `touse'==1,outcome(`varlist') ///
			treat(`treat') unit(`newid') time(`newtime') ///
			cov(`cov') method("ife") force("`force'") r(`fnum') ///
			tol(`tol') maxiterations(`maxiterations') 
			
			if(e(converge)==0){
				restore
				continue
			}
				
			qui gen `spe'=(`varlist'-`counter')^2 if `validation'==`i' & `touse'==1
			qui sum `spe' if `validation'==`i' & `touse'==1

			if r(N)!=0 {
				post `sim' (r(N)) (r(mean))
			}

			restore
			//di as res "Fold `i' finished"
		}
		postclose `sim'


		preserve
		use `results',clear
		tempvar weight_mean
		egen `weight_mean'=wtmean(spe),weight(N)
		qui sum `weight_mean'
		local mspe = string(round(r(mean),.001))
		post `final_sim' (`fnum') (r(mean))
		di as txt "ife r=`fnum' force=`force' mspe=`mspe'"
		restore
	}
	postclose `final_sim'
}

if("`method'"=="mc" | "`method'"=="both"){

	qui postfile `final_sim2' lambda mspe using `final_results2',replace
	//get lambda list
	tempvar FE1 FE2 e
	if("`force'"=="two-way"){
		qui reghdfe `varlist' `cov' if `treat'==0 & `touse'==1, ab(`FE1'=`newid' `FE2'=`newtime') resid
	}
	if("`force'"=="unit"){
		qui reghdfe `varlist' `cov' if `treat'==0 & `touse'==1, ab(`FE1'=`newid') resid
	}
	if("`force'"=="unit"){
		qui reghdfe `varlist' `cov' if `treat'==0 & `touse'==1, ab(`FE2'=`newtime') resid
	}
	if("`force'"=="none"){
		qui reghdfe `varlist' `cov' if `treat'==0 & `touse'==1, noabsorb resid
	}
		
	qui predict `e',residual
		
	qui mata: eig_v("`e'","`treat'","`newid'","`newtime'")
		
	local lambda_max=log10(r(max_sing))
	local lambda_by = 3/(`nlambda' - 2)
	local start_lambda= 10^(`lambda_max')
		
	if("`lambda'"==""){
		if(`nlambda'<3){
			di as err "nlambda should be larger than 2."
			exit
		}
	
		
		local lambda `start_lambda'
		
		forval num=2/`nlambda'{
			local lambda_add=10^(`lambda_max' - (`num' - 1)*`lambda_by')
			local lambda `lambda' `lambda_add'   
		}		
					
	}
		
	foreach lambda_grid in `lambda' {
		qui postfile `sim' N spe using `results',replace

		forval i=1/`kfold' {
			preserve
			tempvar counter spe TE S ATTs
			
			qui fect_counter `counter' `TE' `S' `ATTs' if `validation'!=`i' & `touse'==1,outcome(`varlist') ///
			treat(`treat') unit(`newid') time(`newtime') ///
			cov(`cov') method("mc")  force(`force') ///
			tol(`tol') maxiterations(`maxiterations') lambda(`lambda_grid')
			
			if(e(converge)==0){
				restore
				continue
			}

			qui gen `spe'=(`varlist'-`counter')^2 if `validation'==`i' & `touse'==1
			qui sum `spe' if `validation'==`i' & `touse'==1
			if r(N)!=0 {
				post `sim' (r(N)) (r(mean))
			}
				restore
		}
		postclose `sim'

		preserve
		use `results',clear
		tempvar weight_mean
		egen `weight_mean'=wtmean(spe),weight(N)
		qui sum `weight_mean'
		post `final_sim2' (`lambda_grid') (r(mean))
		local mspe = string(round(r(mean),.001))
		local lambda_print = string(round(`lambda_grid',.0001))
		local lambda_norm_print = string(round(`lambda_grid'/`start_lambda',.001))
		di as txt "mc: lambda=`lambda_print' lambda.norm=`lambda_norm_print' mspe=`mspe'"
		restore
	}
	postclose `final_sim2'
}

if("`method'"=="bspline"){
	qui postfile `final_sim' nknots mspe using `final_results',replace
	if(`nknots'>7 | `nknots'<3){
		dis as err "nkots must be between 3 and 7"
		exit
	}
	
	forval knot=3/`nknots' {
		qui postfile `sim' N spe using `results',replace

		forval i=1/`kfold' {
			preserve
			tempvar counter spe TE S ATTs
			qui fect_counter `counter' `TE' `S' `ATTs' if `validation'!=`i' & `touse'==1,outcome(`varlist') ///
			treat(`treat') unit(`newid') time(`newtime') ///
			cov(`cov') method("bspline") nknots(`knot') force(`force')

			qui gen `spe'=(`varlist'-`counter')^2 if `validation'==`i' & `touse'==1
			qui sum `spe' if `validation'==`i' & `touse'==1
			if r(N)!=0 {
				post `sim' (r(N)) (r(mean))
			}
				restore
		}
		postclose `sim'

		preserve
		use `results',clear
		tempvar weight_mean
		egen `weight_mean'=wtmean(spe),weight(N)
		qui sum `weight_mean'
		post `final_sim' (`knot') (r(mean))
		local mspe = string(round(r(mean),.001))
		di as txt "bspline nknots=`knot' mspe=`mspe'"
		restore
	}
	
	
	postclose `final_sim'
}

if("`method'"=="polynomial"){
	qui postfile `final_sim' degree mspe using `final_results',replace
	if(`degree'<1){
		dis as err "degree must be a positive integer."
		exit
	}
	
	forval dg=1/`degree' {
		qui postfile `sim' N spe using `results',replace

		forval i=1/`kfold' {
			preserve
			tempvar counter spe TE S ATTs
			qui fect_counter `counter' `TE' `S' `ATTs' if `validation'!=`i' & `touse'==1,outcome(`varlist') ///
			treat(`treat') unit(`newid') time(`newtime') ///
			cov(`cov') method("polynomial") degree(`dg') force(`force')

			qui gen `spe'=(`varlist'-`counter')^2 if `validation'==`i' & `touse'==1
			qui sum `spe' if `validation'==`i' & `touse'==1
			if r(N)!=0 {
				post `sim' (r(N)) (r(mean))
			}
				restore
		}
		postclose `sim'

		preserve
		use `results',clear
		tempvar weight_mean
		egen `weight_mean'=wtmean(spe),weight(N)
		qui sum `weight_mean'
		post `final_sim' (`dg') (r(mean))
		local mspe = string(round(r(mean),.001))
		di as txt "polynomial degree=`dg' mspe=`mspe'"
		restore
	}
	
	
	postclose `final_sim'
}
ereturn clear							   
preserve
if("`method'"=="ife"){
	use `final_results',clear
	mkmat r mspe, matrix(CV)
	ereturn matrix CV = CV
	sort mspe
	qui sum mspe in 1
	local min_mspe=r(mean)
	ereturn scalar min_mspe=`min_mspe'
	qui sum r in 1
	local optimal_r=r(mean)
	ereturn scalar optimal_parameter=`optimal_r'
	if(`optimal_r'==0){
		ereturn scalar method=0
	}
	else{
		ereturn scalar method=1
	}
	di as res "optimal r=`optimal_r' in fe/ife model"
	restore	
}
if("`method'"=="mc"){
	use `final_results2',clear
	mkmat lambda mspe, matrix(CV)
	ereturn matrix CV = CV
	sort mspe
	qui sum mspe in 1
	local min_mspe=r(mean)
	ereturn scalar min_mspe=`min_mspe'
	qui sum lambda in 1
	local optimal_lambda=string(round(r(mean),.001))
	ereturn scalar optimal_parameter=`optimal_lambda'
	ereturn scalar method = 2
	di as res "optimal lambda=`optimal_lambda' in mc model"
	restore
}
if("`method'"=="bspline"){
	use `final_results',clear
	mkmat nknots mspe, matrix(CV)
	ereturn matrix CV = CV
	sort mspe
	qui sum mspe in 1
	local min_mspe=r(mean)
	ereturn scalar min_mspe=`min_mspe'
	qui sum nknots in 1
	local optimal_nknots=string(round(r(mean),.001))
	ereturn scalar optimal_parameter=`optimal_nknots'
	ereturn scalar method = 3
	di as res "optimal nknots=`optimal_nknots' in bspline model"
	restore
}
if("`method'"=="polynomial"){
	use `final_results',clear
	mkmat degree mspe, matrix(CV)
	ereturn matrix CV = CV
	sort mspe
	qui sum mspe in 1
	local min_mspe=r(mean)
	ereturn scalar min_mspe=`min_mspe'
	qui sum degree in 1
	local optimal_degree=r(mean)
	ereturn scalar optimal_parameter=`optimal_degree'
	ereturn scalar method = 4
	di as res "optimal degree=`optimal_degree' in polynomial model"
	restore
}
if("`method'"=="both"){
	use `final_results',clear
	mkmat r mspe, matrix(CV)
	matrix CV1 = CV
	sort mspe
	qui sum mspe in 1
	local min_mspe1=r(mean)
	qui sum r in 1
	local optimal_parameter1=r(mean)
	
	use `final_results2',clear
	mkmat lambda mspe, matrix(CV)
	matrix CV2 = CV
	sort mspe
	qui sum mspe in 1
	local min_mspe2=r(mean)
	qui sum lambda in 1
	local optimal_parameter2=r(mean)
	
	if(`min_mspe1'<=`min_mspe2'){
		di as res "choose fe/ife model with optimal r=`optimal_parameter1'"
		ereturn matrix CV=CV1
		ereturn scalar min_mspe=`min_mspe1'
		if(`optimal_parameter1'==0){
			ereturn scalar method=0
		}
		else{
			ereturn scalar method=1
		}
		ereturn scalar optimal_parameter=`optimal_parameter1'
	}
	else{
		ereturn matrix CV=CV2
		ereturn scalar min_mspe=`min_mspe2'
		ereturn scalar optimal_parameter=`optimal_parameter2'
		local optimal_parameter2=string(round(`optimal_parameter2',.001))
		di as res "choose mc model with optimal lambda=`optimal_parameter2'"
		ereturn scalar method=2
	}
}
							   						   
end

program define placebo_Test,eclass
syntax varlist(min=1 max=1) , Treat(varlist min=1 max=1) ///
								  Unit(varlist min=1 max=1) ///
								  Time(varlist min=1 max=1) ///
								[ cov(varlist) ///
								  force(string) ///
								  degree(integer 3) ///
								  nknots(integer 3) ///
								  r(integer 3) ///
								  lambda(real 0.5) ///
								  method(string) ///
								  alpha(real 0.05) ///
								  vartype(string) ///
								  nboots(integer 200) ///
								  tol(real 1e-4) ///
								  maxiterations(integer 5000) ///
								  seed(integer 12345678) ///
								  minT0(integer 5) ///
								  maxmissing(integer 0) ///
								  preperiod(integer -999999) ///
								  offperiod(integer 999999) ///
								  placeboperiod(integer 3) ///
								  Xlabel(string) ///
								  Ylabel(string) ///
								  Title(string) ///
								  Saving(string) ///
								]

set trace off
di as txt "{hline}"	
di as txt "Placebo Test..."
tempvar newid newtime touse
qui gen `touse'=1
qui egen `newid'=group(`unit')
qui egen `newtime'=group(`time')
sort `newid' `newtime'
local lag=`placeboperiod'

//generate placebotreat
tempvar ptreat
qui mata:p_treat("`treat'","`newid'", "`newtime'","`ptreat'",`lag')
//generate true s
tempvar true_s
qui mata:gen_s("`treat'","`newid'", "`newtime'","`true_s'")

/* Threshold of touse */
tempvar ftreat notreatnum notmissingy missingy
gen `ftreat'=0
qui replace `ftreat'=1 if `ptreat'==0 & `varlist'!=. //the number of training data
bys `newid':egen `notreatnum'=sum(`ftreat')
qui replace `touse'=0 if `notreatnum'<`minT0'

if(`maxmissing'>0){
	bys `newid':egen `notmissingy'=count(`varlist')
	qui sum `newtime'
	local TT = r(max)-r(min)
	qui gen `missingy'=`TT'-`notmissingy'
	qui replace `touse'=0 if `missingy'>`maxmissing'
}
qui drop if `touse'==0
/* Threshold of touse END*/

preserve
tempvar counter TE S ATTs

qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`ptreat') unit(`newid') time(`newtime')  ///
method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
maxiterations(`maxiterations') lambda(`lambda')

qui sum `TE' if `true_s'<=0 & `true_s'>-`lag' & `touse'==1
local PlaceboATT=r(mean)

forvalue s=`preperiod'/`offperiod' {

	qui sum `TE' if `true_s'==`s' & `touse'==1
	
	if r(N)==0{
		di in red "No observations for s=`s'"
		local s_index=`s'-`preperiod'
		local att`s_index' = .
		local N`s_index'=0
	}
	else{
		local s_index=`s'-`preperiod'
		local att`s_index' = r(mean)
		local N`s_index'=r(N)
	}
	
}
restore
 
tempname sim sim2
tempfile results results2
qui postfile `sim' ATT using `results',replace
qui postfile `sim2' s ATTs using `results2',replace



if("`vartype'"=="bootstrap"){
	di as txt "Bootstrapping..."
	forvalue i=1/`nboots'{
		preserve
		tempvar counter TE S ATTs
		bsample, cluster(`newid') idcluster(boot_id) 
		drop `newid'
		rename boot_id `newid'
			
		capture qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`ptreat') unit(`newid') time(`newtime')  ///
		method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
		maxiterations(`maxiterations') lambda(`lambda')
			
		if _rc!=0 {
			restore
			continue
		}
			
		/* ATT */
		qui sum `TE' if `true_s'<=0 & `true_s'>-`lag' & `touse'==1
		if r(mean)!=.{
			post `sim' (r(mean))
		}
			
		/* ATTs */
		forvalue si=`preperiod'/`offperiod' {
			qui sum `ATTs' if `true_s'==`si' & `touse'==1
			if r(mean)!=.{
				post `sim2' (`si') (r(mean))
			}
		}
			
		if mod(`i',100)==0 {
			di as txt "ATT Estimation: Already Bootstrapped `i' Times"
		}
		restore
		}
		postclose `sim'
		postclose `sim2'
}
	
if("`vartype'"=="jackknife"){
	//di as txt "{hline}"	
	di as txt "Jackknifing..."
	tempvar order order_mean order_rank
	bys `newid': gen `order'=runiform()
	bys `newid': egen `order_mean'=mean(`order')
	sort `order_mean'
	egen `order_rank'=group(`order_mean')
	qui sum `newid'
	local max_id=r(max)
	forvalue i=1/`max_id'{
		preserve
		tempvar counter TE S ATTs
		qui drop if `order_rank'==`i'
			
		capture qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`ptreat') unit(`newid') time(`newtime')  ///
		method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
		maxiterations(`maxiterations') lambda(`lambda')
			
		if _rc!=0 {
			restore
			continue
		}
			
		/* ATT */
		qui sum `TE' if `true_s'<=0 & `true_s'>-`lag' & `touse'==1
		if r(mean)!=.{
			post `sim' (r(mean))
		}
			
		/* ATTs */
		forvalue si=`preperiod'/`offperiod' {
			qui sum `ATTs' if `true_s'==`si' & `touse'==1
			if r(mean)!=.{
				post `sim2' (`si') (r(mean))
			}
		}
			
		//di as txt "Jackknife: Round `i' Finished"
		restore
		}
		postclose `sim'
		postclose `sim2'
}
	
	
//Placebo_ATT
if("`vartype'"=="bootstrap"){
	preserve
	use `results',clear
	tempname ci placebo_ci_att
	qui sum ATT
	local Placebo_ATTsd=r(sd) //to save
	local twosidel=100*`alpha'/2
	local twosideu=100*(1-`alpha'/2)
	local twoside=100-`alpha'*100
	
	qui _pctile ATT,p(`twosidel' ,`twosideu')
	matrix `placebo_ci_att'=(r(r1),r(r2)) //to save
	matrix rownames `placebo_ci_att' = "Confidence Interval" 
	matrix colnames `placebo_ci_att' = "Lower Bound" "Upper Bound"
	if r(r1)>0 | r(r2)<0 {
		di "Placebo Test Fail"
	}
	else {
		di "Placebo Test Pass"
	}

	local placebo_z_score = `PlaceboATT'/`Placebo_ATTsd'
	local placebo_p_value = 2*(1-normal(abs(`placebo_z_score')))
	
	local placebo_pvalue=round(`placebo_p_value',0.001)
	local placebo_pvalueplot=string(`placebo_pvalue')
	

	//ATTs
	tempname sim_plot
	tempfile results_plot
	qui postfile `sim_plot' s atts att_lb att_ub s_N using `results_plot',replace
	
	qui use `results2',clear

	forvalue s=`preperiod'/`offperiod' {
		qui sum ATTs if s==`s'
		local attsd_temp=r(sd)
		qui _pctile ATTs if s==`s',p(`twosidel' ,`twosideu')
		matrix `ci'=(r(r1),r(r2))
		local s_index=`s'-`preperiod'
		//post `sim_plot' (`s') (`att`s_index'') (`ci'[1,1]) (`ci'[1,2]) (`N`s_index'')
		
		if("`vartype'"=="bootstrap"){
			post `sim_plot' (`s') (`att`s_index'') (`ci'[1,1]) (`ci'[1,2]) (`N`s_index'')
		}
		if("`vartype'"=="jackknife"){
			local tvalue = invttail(`max_id'-1,`alpha'/2)
			local ub_jack = `att`s_index''+`tvalue'*`attsd_temp'
			local lb_jack = `att`s_index''-`tvalue'*`attsd_temp'
			post `sim_plot' (`s') (`att`s_index'') (`lb_jack') (`ub_jack') (`N`s_index'')
		}
	}
	postclose `sim_plot'
	restore
}


if("`vartype'"=="jackknife"){
	preserve
	use `results',clear
	tempname ci placebo_ci_att
	qui sum ATT
	local Placebo_ATTsd=r(sd)*sqrt(`max_id') //to save
	
	local tvalue = invttail(`max_id'-1,`alpha'/2)
	local ub_jack_p = `PlaceboATT'+`tvalue'*`Placebo_ATTsd'
	local lb_jack_p = `PlaceboATT'-`tvalue'*`Placebo_ATTsd'
		
	matrix `placebo_ci_att'=(`lb_jack_p',`ub_jack_p') //to save
	matrix rownames `placebo_ci_att' = "Confidence Interval" 
	matrix colnames `placebo_ci_att' = "Lower Bound" "Upper Bound"
	

	//p-value
	local placebo_z_score = `PlaceboATT'/`Placebo_ATTsd'
	local placebo_p_value = 2*(1-normal(abs(`placebo_z_score')))
	
	local placebo_pvalue=round(`placebo_p_value',0.001)
	local placebo_pvalueplot=string(`placebo_pvalue')

	//ATTs
	tempname sim_plot
	tempfile results_plot
	qui postfile `sim_plot' s atts att_lb att_ub s_N using `results_plot',replace
	
	qui use `results2',clear

	forvalue s=`preperiod'/`offperiod' {
		qui sum ATTs if s==`s'
		local attsd_temp=r(sd)*sqrt(`max_id')
		//qui _pctile ATTs if s==`s',p(`twosidel' ,`twosideu')
		//matrix `ci'=(r(r1),r(r2))
		local s_index=`s'-`preperiod'
		//post `sim_plot' (`s') (`att`s_index'') (`ci'[1,1]) (`ci'[1,2]) (`N`s_index'')
		
		if("`vartype'"=="jackknife"){
			local tvalue = invttail(`max_id'-1,`alpha'/2)
			local ub_jack = `att`s_index''+`tvalue'*`attsd_temp'
			local lb_jack = `att`s_index''-`tvalue'*`attsd_temp'
			post `sim_plot' (`s') (`att`s_index'') (`lb_jack') (`ub_jack') (`N`s_index'')
		}
	}
	postclose `sim_plot'
	restore
}



// Draw ATTs plot
preserve
qui use `results_plot',clear
qui tsset s
local CIlevel=100*(1-`alpha')
qui egen max_atts=max(att_ub)
qui egen max_N=max(s_N)
qui sum max_N
local max_N=r(mean)
local axis2_up=4*`max_N'
qui sum max_atts
local max_atts=1.2*r(mean)
if `max_atts'<0 {
	local max_atts=0
}
qui egen min_atts=min(att_lb)
qui sum min_atts
local min_atts=1.2*r(mean)
if `min_atts'>0 {
	local min_atts=0
}
qui gen y0=0
local placebo_line=`lag'-1

if(abs(`max_atts')>abs(`min_atts')){
		local min_atts=-`max_atts'*0.8
	}
	else{
		local max_atts=-`min_atts'*0.8
}

/* Title */
local xlabel = cond("`xlabel'"=="","Time relative to the Treatment","`xlabel'")
local ylabel = cond("`ylabel'"=="","Average Treatment Effect","`ylabel'")
local title = cond("`title'"=="","Placebo Test","`title'")
local neg_lag=-(`lag'-1)

twoway (rarea att_lb att_ub s, color(gray%30) lcolor(gray) yaxis(1)) ///
(rarea att_lb att_ub s if s>-`lag' & s<=0, color(blue%30) lcolor(blue) yaxis(1)) ///
(line atts y0 s,lcolor(black gray) yaxis(1) lpattern(solid) lwidth(1.1)) ///
(scatter atts s if s>-`lag' & s<=0,mcolor(blue) msymbol(O) yaxis(1) msize(small)) ///
(bar s_N s,yaxis(2) barwidth(0.5) color(midblue%50)), ///
xline(0 -`placebo_line', lcolor(midblue) lpattern(dash)) ///
ysc(axis(1) r(`min_atts' `max_atts')) ///
ysc(axis(2) r(0 `axis2_up')) ///
ylabel(0 `max_N',axis(2)) ///
xlabel(`preperiod' `neg_lag' 0 `offperiod') ///
xtick(`preperiod'(1)`offperiod') ///
ytitle(`ylabel',axis(1)) ///
ytitle("Num of observations",axis(2)) ///
xtitle(`xlabel') ///
title(`title') ///
text(`max_atts' `preperiod' "Placebo Test p-value: `placebo_pvalueplot'",place(e)) ///
scheme(s2mono) ///
graphr(fcolor(ltbluishgray8)) ///
note("`CIlevel'% Confidence Interval") ///
legend(order( 1 "ATT(`CIlevel'% CI)" 2 "Placebo Region" 3 "ATT")) 


if("`saving'"!=""){
   cap graph export `saving',replace
} 
restore


ereturn scalar placebo_pvalue=`placebo_pvalue'
ereturn scalar placebo_ATT_mean=`PlaceboATT'
ereturn scalar placebo_ATT_sd=`Placebo_ATTsd'
ereturn matrix placebo_CI=`placebo_ci_att'


end

program define permutation,eclass
syntax varlist(min=1 max=1) , Treat(varlist min=1 max=1) ///
								  Unit(varlist min=1 max=1) ///
								  Time(varlist min=1 max=1) ///
								[ cov(varlist) ///
								  force(string) ///
								  degree(integer 3) ///
								  nknots(integer 3) ///
								  r(integer 3) ///
								  lambda(real 0.5) ///
								  method(string) ///
								  nboots(integer 200) ///
								  tol(real 1e-4) ///
								  maxiterations(integer 5000) ///
								]
								
set trace off
di as txt "{hline}"	
di as txt "Permutation Test..."
tempvar newid newtime
qui egen `newid'=group(`unit')
qui egen `newtime'=group(`time')
sort `newid' `newtime'

/* estimate ATT */
preserve
tempvar counter TE S ATTs

qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`treat') unit(`newid') time(`newtime')  ///
method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
maxiterations(`maxiterations') lambda(`lambda')

sort `newid' `newtime'
qui sum `TE' if `treat'==1
local ATT=r(mean) //to save

restore

/* Simulation */
tempname sim_permu
tempfile results_permu
qui postfile `sim_permu' ATT using `results_permu',replace

forvalue i=1/`nboots'{
	preserve
	tempvar permutreat
	qui mata:permute("`treat'","`newid'","`newtime'","`permutreat'")
	
	tempvar counter TE S ATTs
	qui fect_counter `counter' `TE' `S' `ATTs',outcome(`varlist') treat(`permutreat') unit(`newid') time(`newtime')  ///
	method("`method'") force("`force'") cov(`cov') nknots(`nknots') degree(`degree') r(`r') tol(`tol') ///
	maxiterations(`maxiterations') lambda(`lambda')
	
	qui sum `TE' if `permutreat'==1
	if r(mean)!=.{
		post `sim_permu' (r(mean))
	}
	
	if mod(`i',100)==0 {
			di as txt "Permutation Test: Already Simulated `i' Times"
	}
	restore
}
postclose `sim_permu'

preserve
qui use `results_permu',clear
qui drop if ATT<`ATT'
qui sum ATT
local pvalue=r(N)/`nboots'
ereturn scalar permutation_pvalue=`pvalue'
local pvalue_print=string(round(`pvalue',.001))
di as res "Permutation Test: p value=`pvalue_print'"
restore


end
*********************************************************mata
mata:
mata clear

void treat_fill(string missing_treat,string unit, string time)
{
	real matrix treat,panel_treat,x
	real scalar minid,maxid,mintime,maxtime,rownum,colnum,i,j
	st_view(treat=.,.,missing_treat)
	st_view(x=.,.,(unit,time))

	minid=min(x[,1])
	maxid=max(x[,1])
	mintime=min(x[,2])
	maxtime=max(x[,2])
	rownum=maxid-minid+1
	colnum=maxtime-mintime+1

	panel_treat=treat
	panel_treat=rowshape(panel_treat,rownum)

	for(i=1;i<=rownum;i++) {
		if(hasmissing(panel_treat[i,1])==1) {
			panel_treat[i,1]=0
		}
	
		for(j=2;j<=colnum;j++) {
			if(hasmissing(panel_treat[i,j])==1) {
				panel_treat[i,j]=panel_treat[i,j-1]
			}
		}
	}
	treat=colshape(panel_treat,1)
	st_store(.,missing_treat,treat)
}


void gen_s(string missing_treat,string unit, string time, string outputs)
{
	real matrix treat,panel_treat,x,panel_s
	real scalar minid,maxid,mintime,maxtime,rownum,colnum,i,j,state,start,cut,k
	st_view(treat=.,.,missing_treat)
	st_view(x=.,.,(unit,time))

	minid=min(x[,1])
	maxid=max(x[,1])
	mintime=min(x[,2])
	maxtime=max(x[,2])
	rownum=maxid-minid+1
	colnum=maxtime-mintime+1

	panel_treat=treat
	panel_treat=rowshape(panel_treat,rownum)
	panel_s=panel_treat

	for(i=1;i<=rownum;i++) {
		if(panel_treat[i,1]==0){
			state=0
			start=1
			cut=1
			panel_s[i,1]=.
		}
		else{
			state=1
			panel_s[i,1]=1
		}
		for(j=2;j<=colnum;j++) {
			if(panel_treat[i,j]==0 & state==1) {
				state=0
				start=j
				cut=j
				panel_s[i,j]=.
			}
			else if(panel_treat[i,j]==0 & state==0) {
				cut=cut+1
				panel_s[i,j]=.
			}
			else if(panel_treat[i,j]==1 & state==1) {
				panel_s[i,j]=1+panel_s[i,j-1]
			}
			else if(panel_treat[i,j]==1 & state==0){
				for(k=start;k<=cut;k++) {
					panel_s[i,k]=k-cut
				}
				panel_s[i,j]=1
				state=1
			}
		}
	}
	panel_s=colshape(panel_s,1)
	st_addvar("int", outputs)
	st_store(., outputs,panel_s)
}

void ife(string outcome, string cov, string treat,  string unit, string time,string force ,real r, real Tol, real iter, string newvarname, string alpha, string xi, string mu)
{
	real matrix Y, Y_use, Y_hat, Y_hat_use, tr, use, X, X_use, XX_inv, XY, W, beta_hat, W_hat, W_all_mean, W_unit_mean, W_time_mean, W_max
	real vector tr_index, use_index
	real scalar p,num_obs,i,num_tr,num_use,j,k, num_unit, num_time,m,trans
	real matrix unit_index, time_index
	real matrix alpha_hat, xi_hat, mu_hat, ife_hat
	real matrix target_index
	real matrix U, Vt, svd_val,target_svd, ife_matrix, Y_predict, Y_predict_old, Y_predict_delta

	st_view(tr=.,.,treat)
	use=(tr:==0)
	num_use=sum(use)
	num_tr=sum(tr)
	st_view(X=.,.,(cov))
	X = editmissing(X,0)
	
	st_view(Y=.,.,outcome)
	Y = editmissing(Y,0)
	Y_use = Y:*use
	num_obs=rows(Y)
	p=cols(X)
	
	st_view(unit_index=.,.,unit)
	st_view(time_index=.,.,time)
	num_unit=rows(uniqrows(unit_index))
	num_time=rows(uniqrows(time_index))
	
	
	//get XX_inv
	if(p>0){
		X_use = X:*use
		XX_inv = transposeonly(X_use)*X_use
		_invsym(XX_inv)
	}
	
	//get index
	tr_index=selectindex(tr)
	use_index=selectindex(use)
	
	//initialization
	st_view(alpha_hat=.,.,alpha)
	st_view(xi_hat=.,.,xi)
	st_view(mu_hat=.,.,mu)	
	ife_hat = J(num_obs,1,0)
	//Y_hat = Y
	
	//start: first round
	for(m=1;m<=iter;m++) {
		Y_hat = Y-mu_hat-alpha_hat-xi_hat-ife_hat
		Y_hat_use = Y_hat:*use
	
		if(p>0){
			XY = transposeonly(X_use)*Y_hat_use
			beta_hat = XX_inv*XY
		}
		
		W=J(num_obs,1,0)
		if(p>0){
			W[use_index,]= Y[use_index,]-X[use_index,]*beta_hat
		}else{
			W[use_index,]= Y[use_index,]
		}
	
		W[tr_index,] = mu_hat[tr_index,]  + alpha_hat[tr_index,] + xi_hat[tr_index,] + ife_hat[tr_index,] 
	
		//get W_hat
		W_all_mean=J(num_obs,1,mean(W))
		W_unit_mean=J(num_obs,1,0)
		W_time_mean=J(num_obs,1,0)
			
		if(force=="two-way"|force=="unit"){
			for(j=1;j<=num_unit;j++){
				target_index = (unit_index:==j)
				W_unit_mean = W_unit_mean:+(target_index*(sum(W:*target_index))/num_time)
			}
		}
		
		if(force=="two-way"|force=="time"){
			for(k=1;k<=num_time;k++){
				target_index = (time_index:==k)
				W_time_mean = W_time_mean:+(target_index*(sum(W:*target_index))/num_unit)
			}
		}
		
		if(force=="two-way"){
			W_hat = W - (W_unit_mean+W_time_mean) + W_all_mean
		}
		if(force=="unit"){
			W_hat = W - W_unit_mean
		}
		if(force=="time"){
			W_hat = W - W_time_mean
		}
		if(force=="none"){
			W_hat = W - W_all_mean
		}
		
		W_hat=rowshape(W_hat,num_unit)
	
		//svd
		if(rows(W_hat)<cols(W_hat)){
			trans=1
			W_hat = transposeonly(W_hat)
		}else{
			trans=0
		}
		
		W_max = num_unit*num_time
		W_hat = W_hat/W_max
		
		svd(W_hat,U=.,svd_val=.,Vt=.)
		target_svd=J(length(svd_val),1,0)
		for(i=1;i<=r;i++){
			target_svd[i,]=1
		}
		svd_val=svd_val:*target_svd
		ife_matrix = U[|1,1\.,r|]*diag(svd_val)[|1,1\r,r|]*Vt[|1,1\r,.|]
		
		if(trans==1){
			ife_matrix=transposeonly(ife_matrix)
		}
		ife_matrix=ife_matrix*W_max
	
		//update
		ife_hat = colshape(ife_matrix,1)
		if(force=="two-way"|force=="unit"){
			alpha_hat = W_unit_mean-W_all_mean
		}
		if(force=="two-way"|force=="time"){
			xi_hat = W_time_mean - W_all_mean
		}
		mu_hat = W_all_mean
		
		//predict
		Y_predict = mu_hat+alpha_hat+xi_hat+ife_hat
		if(p>0){
			Y_predict = Y_predict + X*beta_hat
		}
		
		if(m==1){
			Y_predict_old = Y_predict
		}else{
			//check converge
			
			Y_predict_delta = Y_predict[use_index,]-Y_predict_old[use_index,]
			
			//sqrt(sum((Y_predict_delta):*Y_predict_delta))/num_use
			
			if (sqrt(sum(Y_predict_delta:*Y_predict_delta))/sqrt(sum(Y_predict:*Y_predict))<Tol){
				st_numscalar("r(stop)", 1)
				break
			} 
			st_numscalar("r(stop)", 0)
			Y_predict_old = Y_predict
		}
	}
	
	st_addvar("double", newvarname)
	st_store(., newvarname,Y_predict)

	if(p>0){
		st_matrix("r(coef)",transposeonly(beta_hat))
	}
	st_numscalar("r(cons)", mean(W_all_mean))
	
}



void mc(string outcome, string cov, string treat,  string unit, string time,string force ,real lambda, real Tol, real iter, string newvarname, string alpha, string xi, string mu)
{
	real matrix Y, Y_use, Y_hat, Y_hat_use, tr, use, X, X_use, XX_inv, XY, W, beta_hat, W_hat,W_max,WW_hat ,W_all_mean, W_unit_mean, W_time_mean
	real vector tr_index, use_index
	real scalar p,num_obs,i,num_tr,num_use,j,k, num_unit, num_time,m,trans,crit
	real matrix unit_index, time_index
	real matrix alpha_hat, xi_hat, mu_hat, mc_hat
	real matrix target_index
	real matrix U, Vt, svd_val,target_svd, mc_matrix, Y_predict, Y_predict_old, Y_predict_delta

	st_view(tr=.,.,treat)
	use=(tr:==0)
	num_use=sum(use)
	num_tr=sum(tr)
	st_view(X=.,.,(cov))
	X = editmissing(X,0)
	
	st_view(Y=.,.,outcome)
	Y = editmissing(Y,0)
	Y_use = Y:*use
	num_obs=rows(Y)
	p=cols(X)
	
	st_view(unit_index=.,.,unit)
	st_view(time_index=.,.,time)
	num_unit=rows(uniqrows(unit_index))
	num_time=rows(uniqrows(time_index))
	
	
	//get XX_inv
	if(p>0){
		X_use = X:*use
		XX_inv = transposeonly(X_use)*X_use
		_invsym(XX_inv)
	}
	
	//get index
	
	tr_index=selectindex(tr)
	use_index=selectindex(use)
		
	
	//initialization
	st_view(alpha_hat=.,.,alpha)
	st_view(xi_hat=.,.,xi)
	st_view(mu_hat=.,.,mu)	
	mc_hat = J(num_obs,1,0)
	//Y_hat = Y
	
	W_max = num_unit*num_time
	
	//start: first round
	for(m=1;m<=iter;m++) {
		Y_hat = Y-mu_hat-alpha_hat-xi_hat-mc_hat
		Y_hat_use = Y_hat:*use
				
		if(p>0){
			XY = transposeonly(X_use)*Y_hat_use
			beta_hat = XX_inv*XY
		}
		
		W=J(num_obs,1,0)
		if(p>0){
			W[use_index,]= Y[use_index,]-X[use_index,]*beta_hat
		}else{
			W[use_index,]= Y[use_index,]
		}
	
		W[tr_index,] = mu_hat[tr_index,]  + alpha_hat[tr_index,] + xi_hat[tr_index,] + mc_hat[tr_index,] 
	
		//get W_hat
		W_all_mean=J(num_obs,1,mean(W))
		W_unit_mean=J(num_obs,1,0)
		W_time_mean=J(num_obs,1,0)
			
		if(force=="two-way"|force=="unit"){
			for(j=1;j<=num_unit;j++){
				target_index = (unit_index:==j)
				W_unit_mean = W_unit_mean:+(target_index*(sum(W:*target_index))/num_time)
			}
		}
		
		if(force=="two-way"|force=="time"){
			for(k=1;k<=num_time;k++){
				target_index = (time_index:==k)
				W_time_mean = W_time_mean:+(target_index*(sum(W:*target_index))/num_unit)
			}
		}
		
		if(force=="two-way"){
			W_hat = W - (W_unit_mean+W_time_mean) + W_all_mean
		}
		if(force=="unit"){
			W_hat = W - W_unit_mean
		}
		if(force=="time"){
			W_hat = W - W_time_mean
		}
		if(force=="none"){
			W_hat = W - W_all_mean
		}
		W_hat=rowshape(W_hat,num_unit)
	
		//svd
		if(rows(W_hat)<cols(W_hat)){
			trans=1
			W_hat = transposeonly(W_hat)
		}else{
			trans=0
		}
		W_hat = W_hat/W_max
		svd(W_hat,U=.,svd_val=.,Vt=.)		
		svd_val=svd_val:-lambda
		svd_val=svd_val:*(svd_val:>0)
		mc_matrix=U*diag(svd_val)*Vt
		if(trans==1){
			mc_matrix=transposeonly(mc_matrix)
		}
		mc_matrix=mc_matrix*W_max
	
		//update
		mc_hat = colshape(mc_matrix,1)
		if(force=="two-way"|force=="unit"){
			alpha_hat = W_unit_mean-W_all_mean
		}
		if(force=="two-way"|force=="time"){
			xi_hat = W_time_mean - W_all_mean
		}
		mu_hat = W_all_mean
		
		//predict
		Y_predict = mu_hat+alpha_hat+xi_hat+mc_hat
		if(p>0){
			Y_predict = Y_predict + X*beta_hat
		}
		if(m==1){
			Y_predict_old = Y_predict
		}
		else{
			//check converge
			Y_predict_delta = Y_predict[use_index,]-Y_predict_old[use_index,]
			crit=sqrt(sum(Y_predict_delta:*Y_predict_delta))/sqrt(sum(Y_predict:*Y_predict))
			if (crit<Tol){
				st_numscalar("r(stop)", 1)
				break
			} 
			st_numscalar("r(stop)", 0)
			Y_predict_old = Y_predict
		}
	}
	
	st_addvar("double", newvarname)
	st_store(., newvarname,Y_predict)

	if(p>0){
		st_matrix("r(coef)",transposeonly(beta_hat))
	}
	st_numscalar("r(cons)", mean(W_all_mean))
	
}




void val_gen(string treat, string unit, string time, string touse, ///
real fold,real period,string validation,real seed)
{
	real matrix panel_treat,x,panel_touse,groupid,slice_treat,slice_touse,index,targetindex
	real scalar minid,maxid,mintime,maxtime,rownum,colnum,i,j,k,groupnum,colcut,mod,indexcut,num_infold
	st_view(x=.,.,(unit,time,treat,touse))

	minid=min(x[,1])
	maxid=max(x[,1])
	mintime=min(x[,2])
	maxtime=max(x[,2])
	rownum=maxid-minid+1
	colnum=maxtime-mintime+1

	panel_treat=x[,3]
	panel_treat=rowshape(panel_treat,rownum)
	panel_touse=x[,4]
	panel_touse=rowshape(panel_touse,rownum)

	groupid=J(rownum,colnum,.)
	groupnum=1

	if(period>=colnum) {
		_error("CVnobs is too large.")
	}

	if(fold<=1) {
		_error(0)
	}

	colcut=floor(colnum/period)

	if(colcut*period==colnum){
		mod=1
	}
	else{
		mod=0
	}

	for(i=1;i<=rownum;i++) {
		for(j=0;j<colcut;j++) {
			slice_treat=(panel_treat[i,(j*period+1)::((j+1)*period)]:==0)
			slice_touse=panel_touse[i,(j*period+1)::((j+1)*period)]	
			if(sum(slice_touse:*slice_treat)>0) {
				for(k=(j*period+1);k<=(j+1)*period;k++) {
					groupid[i,k]=groupnum
				}
				groupnum=groupnum+1
			}
		}
	
		if(mod==1) {
			continue
		}
	
		slice_treat=(panel_treat[i,(colcut*period+1)::colnum]:==0)
		slice_touse=panel_touse[i,(colcut*period+1)::colnum]
	
		if(sum(slice_touse:*slice_treat)>0) {
			for(k=(colcut*period+1);k<=colnum;k++) {
				groupid[i,k]=groupnum
			}
		groupnum=groupnum+1
		}
	}

	index=1::(groupnum-1)
	rseed(seed)
	_jumble(index)
	num_infold=floor((groupnum-1)/fold)

	if(num_infold==0) {
		_error("kfold is too large.")
	}

	for(i=0;i<fold;i++) {
		targetindex=index[(i*num_infold+1)::(i+1)*num_infold]
		for(j=1;j<=num_infold;j++) {
			_editvalue(groupid,targetindex[j],-(i+1))
		}
	}

	_editmissing(groupid,0)
	groupid=-groupid:*(groupid:<0)
	groupid=colshape(groupid,1)
	st_store(.,validation,groupid)
}


void eig_v(string outcome, string treat, string unit, string time)
{
	real matrix tr,use,x
	real scalar minid,maxid,rownum,num
	real matrix out_outcome,index,U,s,Vt

	st_view(tr=.,.,treat)
	use=(tr:==0)
	st_view(x=.,.,(unit,time,outcome))

	minid=min(x[,1])
	maxid=max(x[,1])
	rownum=maxid-minid+1
	num=rows(use)
	index=rowshape(use,rownum)
	out_outcome=editmissing(rowshape(x[,3],rownum),0):*index
	
	out_outcome=out_outcome/num
	
	s=svdsv(out_outcome)

	st_numscalar("r(max_sing)", max(s))
	
}

void p_treat(string Treat,string unit, string time, string outputs,real period)
{
	real matrix treat,panel_treat,x,placebotreat
	real scalar minid,maxid,mintime,maxtime,rownum,colnum,i,j,k
	st_view(treat=.,.,Treat)
	st_view(x=.,.,(unit,time))

	minid=min(x[,1])
	maxid=max(x[,1])
	mintime=min(x[,2])
	maxtime=max(x[,2])
	rownum=maxid-minid+1
	colnum=(maxtime-mintime)+1

	panel_treat=treat
	panel_treat=rowshape(panel_treat,rownum)

	placebotreat=panel_treat

	for(i=1;i<=rownum;i++){
		for(j=colnum;j>=1;j--){
			if(panel_treat[i,j]==1){
				for(k=1;k<=period;k++){
					if((j-k)>0){
						placebotreat[i,j-k]=placebotreat[i,j-k]+1
					}
				}
			}	 
		}
	}
	placebotreat=placebotreat:>=1
	placebotreat=colshape(placebotreat,1)
	st_addvar("int", outputs)
	st_store(., outputs,placebotreat)
}

void waldF(string scalar Id, string scalar Time, string scalar TE, string scalar ATTs, string scalar S, ///
real scalar from, real scalar to, string scalar to_use)
{
	real matrix panel_s,panel_atts,panel_e,id,s,time,atts,e,touse,panel_touse
	real scalar maxid,maxtime,mintime,timespan,Ot,nominator,denominator,Fobs,i,j,mi
	if(from>to){
		_error("preperiod should less than to")
	}
	
	st_view(id=.,.,Id)
	st_view(s=.,.,S)
	st_view(time=.,.,Time)
	st_view(atts=.,.,ATTs)
	st_view(e=.,.,TE)
	st_view(touse=.,.,to_use)

	maxid=max(id)
	maxtime=max(time)
	mintime=min(time)

	timespan=maxtime-mintime+1
	panel_s=s
	panel_s=rowshape(panel_s,maxid)
	panel_atts=atts
	panel_atts=rowshape(panel_atts,maxid)
	panel_e=e
	panel_e=rowshape(panel_e,maxid)
	panel_touse=touse
	panel_touse=rowshape(panel_touse,maxid)

	Ot=0
	for(i=1;i<=maxid;i++) {
		if(missing(panel_s[i,])==timespan){
			continue
		}
		mi=0
		for(j=1;j<=timespan;j++) {
			if(panel_s[i,j]>=from & panel_s[i,j]<=to & missing(panel_s[i,j])==0 & panel_touse[i,j]==1) {
				mi=mi+1
			}
		Ot=Ot+mi
		mi=0
		}
	}
	nominator=0
	denominator=0
	mi=min((abs(from)+1+to,abs(min(s))+1+to))

	for(i=1;i<=maxid;i++) {
		if(missing(panel_s[i,])==timespan) {
			continue
		}
		for(j=1;j<=timespan;j++) {
			if(panel_s[i,j]>=from & panel_s[i,j]<=to & missing(panel_s[i,j])==0 & panel_touse[i,j]==1 &missing(panel_e[i,j])==0) {
				nominator=nominator+(panel_e[i,j]^2-(panel_e[i,j]-panel_atts[i,j])^2)/mi
				denominator=denominator+((panel_e[i,j]-panel_atts[i,j]))^2/(Ot+mi)
			}
		}
	}
	Fobs=nominator/denominator
	st_numscalar("r(F)", Fobs)
}

void permute(string demissing_treat,string unit, string time, string permu_treat)
{
	real matrix treat,treat2,panel_treat,panel_treat2,x,index
	real scalar minid,maxid,mintime,maxtime,rownum,colnum,i,j
	st_view(treat=.,.,demissing_treat)
	st_view(x=.,.,(unit,time))

	minid=min(x[,1])
	maxid=max(x[,1])
	mintime=min(x[,2])
	maxtime=max(x[,2])
	rownum=maxid-minid+1
	colnum=maxtime-mintime+1

	panel_treat=treat
	panel_treat=rowshape(panel_treat,rownum)
	
	index=minid::maxid
	_jumble(index)
	panel_treat2=panel_treat
	
	for(i=1;i<=rownum;i++) {	
		panel_treat2[i,]=panel_treat[index[i],]
	}
	treat2=colshape(panel_treat2,1)
	st_addvar("int", permu_treat)
	st_store(., permu_treat,treat2)
}

end							   
						   