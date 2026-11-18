/* Model assumptions are intentionally editable. No network calls. */
(function(global){'use strict';
const defaults = {
  startAge: 30, startYear: 2027, startMonths: 12,
  salary: 0, assets: 0, cashShare: 100, rothShare: 0, workplaceShare: 0,
  rent: 0, food: 0, utilities: 0, transport: 0, goods: 0, entertainment: 0,
  medical: 0, renters: 0, travel: 0, misc: 0,
  goldFee: 0, goldMatch: 0, contribution: 0, matchFull: 0, matchHalf: 0,
  raise: 3, roi: 7, optimistic: 10, volatility: 16, inflation: 2.5,
  limitGrowth: 2.5, cashReturn: 2, taxDrag: .5, stateTax: 0,
  marriage: 0, spouseRatio: 0, spouseContribution: 0, spouseMatch: 0,
  spouseAssets: 0, houseRent: 0, spouseOther: 0, health: 0, wedding: 0,
  firstChild: 0, secondChild: 0, youngCost: 0, olderCost: 0,
  emergencyMonths: 3, jobRisk: 3, spouseRisk: 3, switchAge: 32,
  switchRaise: 15, switchCost: 0, switchGap: 0, extraSave: 100,
  backdoor: false, spouseBackdoor: false, spouseGold: false,
  iraLimit: 7500, kLimit: 25500, singleLower: 158000, singleUpper: 173000,
  jointLower: 250000, jointUpper: 260000, otherMagi: 0, seed: 91520
};

// Reproduce the timing, allocation and match rules of database and JSON plans
// created before these variables were editable.
const previousRules = {
  startAge: 22, startYear: 2027, cashShare: 25, rothShare: 25,
  workplaceShare: 5, matchFull: 3, matchHalf: 2, stateTax: 5
};
const forecastYears = 11;
function startingAllocation(s) {
  const cash = clamp(s.cashShare, 0, 100);
  const roth = clamp(s.rothShare, 0, 100 - cash);
  const workplace = clamp(s.workplaceShare, 0, 100 - cash - roth);
  return { cash, roth, workplace, brokerage: 100 - cash - roth - workplace };
}

const clamp=(x,a,b)=>Math.min(b,Math.max(a,x));const living=s=>s.rent+s.food+s.utilities+s.transport+s.goods+s.entertainment+s.medical+s.renters+s.travel+s.misc;
function federal(g,j,f){let x=Math.max(0,g-16600*(j?2:1)*f),last=0,t=0;[12800,52025,109125,208325,264550,661375,Infinity].forEach((v,i)=>{let cap=v*(j?2:1)*f;if(j&&i===5)cap=792100*f;t+=Math.max(0,Math.min(x,cap)-last)*[.1,.12,.22,.24,.32,.35,.37][i];last=cap});return t;}
function taxes(g,p,c,pc,j,f,stateTax=5){return federal(g+p-c-pc,j,f)+Math.max(0,g+p-c-pc-4400*(j?2:1)-3600)*stateTax/100 /* rent deduction proxy, see notes */+ [g,p].reduce((a,v)=>a+Math.min(v,184500*f)*.062+v*.0145+Math.min(v,184500*f)*.0046,0)+Math.max(0,g+p-(j?250000:200000))*.009;}
function allowance(m,lo,hi,lim){return m<=lo?lim:m>=hi?0:Math.min(lim,Math.max(200,Math.ceil(lim*(hi-m)/(hi-lo)/10)*10));}
function match(g,r,s){return g*(Math.min(r,s.matchFull)+Math.min(s.matchHalf,Math.max(0,r-s.matchFull))*.5)/100;}
function plan(s){let g=s.salary,c=Math.min(g*s.contribution/100,s.kLimit),tax=taxes(g,0,c,0,false,1,s.stateTax),m=g-c+s.otherMagi,allow=allowance(m,s.singleLower,s.singleUpper,s.iraLimit),net=(g-c-tax)/12,spend=living(s)+s.goldFee/12,ira=Math.min(Math.max(0,(net-spend)*12),s.backdoor?s.iraLimit:allow),target=(s.rent+s.food+s.utilities+s.transport+s.medical+s.renters)*s.emergencyMonths;return {g,c,tax,net,spend,ira,allow,target,broker:net-spend-ira/12,match:match(g,s.contribution,s)};}
function simulate(s,{n=1500,mode='base',det=false,returnOverride}={}){let seed=s.seed>>>0;const rand=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return(seed+.5)/4294967296};const norm=()=>Math.sqrt(-2*Math.log(rand()))*Math.cos(2*Math.PI*rand());const years=Array.from({length:forecastYears},()=>[]),allocation=startingAllocation(s);for(let j=0;j<n;j++){let h=s.assets*allocation.cash/100,r=s.assets*allocation.roth/100,k=s.assets*allocation.workplace/100,b=s.assets*allocation.brokerage/100,sh=0,sr=0,sk=0,sb=0,debt=0,sd=0,sal=s.salary,ps=s.salary*s.spouseRatio/100;const rentF=det?1:.85+rand()*.45,childF=det?1:.65+rand()*.9,mar=s.marriage+(det?0:Math.floor(rand()*3)-1),weddingF=det?1:.5+rand();for(let i=0;i<forecastYears;i++){let age=s.startAge+i,f=(1+s.inflation/100)**i,idx=(1+s.limitGrowth/100)**i,months=i===0?s.startMonths:12,m=months/12,married=s.marriage>0&&age>=mar;if(i){let raise=det?s.raise/100:clamp(s.raise/100+norm()*.012,-.05,.12);sal*=1+raise;ps*=1+raise}if(mode==='switch'&&age===s.switchAge)sal*=1+s.switchRaise/100;let rr=clamp((returnOverride??s.roi)/100+(det?0:norm()*s.volatility/100),-.85,1.5);let lost=det?0:rand()<s.jobRisk/100?2+Math.floor(rand()*4):0,plost=det?0:rand()<s.spouseRisk/100?2+Math.floor(rand()*4):0;let g=sal*Math.max(0,months-lost-(mode==='switch'&&age===s.switchAge?s.switchGap:0))/12,p=married?ps*Math.max(0,12-plost)/12:0,c=Math.min(g*s.contribution/100,s.kLimit*idx),pc=Math.min(p*s.spouseContribution/100,s.kLimit*idx),em=match(g,s.contribution,s),pm=p*Math.min(s.spouseContribution,s.spouseMatch)/100;let child=0;for(let birth of [s.firstChild,s.secondChild])if(married&&birth>0&&age>=birth&&age-birth<18)child+=(age-birth<5?s.youngCost:s.olderCost)*childF*12*f;let housing=(married?s.houseRent:s.rent)*rentF;let regular=(housing+living(s)-s.rent+(married?s.spouseOther:0)+(age>=26?s.health:0))*12*m*f;let expense=regular+child+s.goldFee+(married&&s.spouseGold?s.goldFee:0)+(married&&age===mar?s.wedding*weddingF:0)+(mode==='switch'&&age===s.switchAge?s.switchCost:0)-(mode==='save'?Math.min(s.extraSave*12*m,regular*.25):0);let tax=taxes(g,p,c,pc,married,idx,s.stateTax),magi=g+p-c-pc+s.otherMagi,lim=Math.round(s.iraLimit*idx/500)*500,lo=(married?s.jointLower:s.singleLower)*idx,hi=(married?s.jointUpper:s.singleUpper)*idx,eligible=allowance(magi,lo,hi,lim);let surplus=g+p-c-pc-tax-expense,share=married?(g+p>0?g/(g+p):1/(1+s.spouseRatio/100)):1;let own=surplus*share,sp=surplus*(1-share);let growth=(1+rr)**m,taxGrowth=Math.max(.05,1+rr-s.taxDrag/100)**m;h*= (1+s.cashReturn/100)**m;r*=growth;k=k*growth+c+em;b*=taxGrowth;sh*=1+s.cashReturn/100;sr*=1+rr;sk=sk*(1+rr)+pc+pm;sb*=Math.max(.05,1+rr-s.taxDrag/100);if(married&&(i===0||age===mar))sb+=s.spouseAssets;debt*=1.08**m;sd*=1.08;let target=(housing+s.food+s.utilities+s.transport+s.medical+s.renters+(married?s.spouseOther*.6:0)+child/12/f)*s.emergencyMonths*f;let ownTarget=target*share,spTarget=target*(1-share);let fill=Math.min(Math.max(0,own),Math.max(0,ownTarget-h));h+=fill;own-=fill;let sf=Math.min(Math.max(0,sp),Math.max(0,spTarget-sh));sh+=sf;sp-=sf;let repay=Math.min(debt,Math.max(0,own));debt-=repay;own-=repay;let srp=Math.min(sd,Math.max(0,sp));sd-=srp;sp-=srp;let ira=Math.min(Math.max(0,own),g,s.backdoor?lim:eligible),pi=married?Math.min(Math.max(0,sp),p,s.spouseBackdoor?lim:eligible):0;let direct=Math.min(ira,eligible),pd=Math.min(pi,eligible),gold=s.goldMatch/100,pg=s.spouseGold?gold:.01;let convTax=(ira-direct)*gold*.29+(pi-pd)*pg*.29;r+=ira*(1+gold);sr+=pi*(1+pg);own-=ira+(ira-direct)*gold*.29;sp-=pi+(pi-pd)*pg*.29;let brokerage=Math.max(0,own),spBroker=Math.max(0,sp);b+=brokerage;sb+=spBroker;if(own<0){let d=Math.min(h,-own);h-=d;own+=d;let e=Math.min(b,-own);b-=e;own+=e;debt+=Math.max(0,-own)}if(sp<0){let d=Math.min(sh,-sp);sh-=d;sp+=d;let e=Math.min(sb,-sp);sb-=e;sp+=e;sd+=Math.max(0,-sp)}let individual=h+r+k+b-debt,house=individual+sh+sr+sk+sb-sd;years[i].push({
        // Combine household values on each path before calculating percentiles.
        houseCash: h+sh, houseRoth: r+sr, houseWorkplace: k+sk, houseBroker: b+sb,
        houseIncome: g+p, ownExpense: expense*share, ownTax: tax*share,
        surplus, ownSurplus: surplus*share, ownDebt: debt,
        ownShortfall: Math.max(0,-surplus*share),
        ownWorkplaceContribution: c, houseWorkplaceContribution: c+pc,
        ownEmployerMatch: em, houseEmployerMatch: em+pm,
        houseIra: ira+pi, houseBrokerageContribution: brokerage+spBroker,
        houseDirect: direct+pd, houseBackdoor: ira-direct+pi-pd,
        individual,house,accessible:h+b-debt,houseAccessible:h+b+sh+sb-debt-sd,real:individual/f,houseReal:house/f,h,r,k,b,sh,sr,sk,sb,debt:debt+sd,g,p,tax,expense,child,regular,ira,pi,direct,backdoor:ira-direct,eligible,lo,hi,magi,brokerage,spBroker,em,contribution:surplus+c+pc+em+pm+ira*gold+pi*pg-convTax-f*0,shortfall:Math.max(0,-surplus)})}}let keys=Object.keys(years[0][0]);return years.map((rows,i)=>{let out={age:s.startAge+i,year:s.startYear+i};for(const key of keys){let a=rows.map(r=>r[key]).sort((a,b)=>a-b);out[key]=[.1,.25,.5,.75,.9].map(p=>a[Math.floor((a.length-1)*p)])}return out});}
const api={defaults,previousRules,forecastYears,startingAllocation,living,plan,simulate,allowance,taxes};if(typeof module!=='undefined')module.exports=api;else global.Trajectory=api;})(globalThis);
