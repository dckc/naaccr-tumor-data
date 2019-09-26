/** data_char_sim.sql -- characterize, simulate data

Copyright (c) 2015 University of Kansas Medical Center
part of the HERON* open source codebase; see NOTICE file for license details.
* http://informatics.kumc.edu/work/wiki/HERON
 
*/

-- Check that NAACCR data dictionary and data is available.
select sectionid from section where 1=0;
select recordId, dateOfDiagnosis from naaccr_extract where 1=0;
select recordId, naaccrNum from tumors_eav where 1=0;
select `naaccr-item-num`, section from record_layout;

-- Check that tumor_item_type from naaccr_txform.sql is available (esp. for valtype_cd)
select valtype_cd from tumor_item_type where 1=0;


create or replace temporary view data_agg_naaccr as
with
cases as (
  select year(dateOfDiagnosis) as dx_yr, count(*) as tumor_qty
  from naaccr_extract
  group by year(dateOfDiagnosis)
)
, with_yr as (
  select year(dateOfDiagnosis) dx_yr
       , eav.*
  from tumors_eav eav
)
-- count data points by item (variable) and year of diagnosis
, by_item_yr as (
  select dx_yr, agg.naaccrId, ty.naaccrNum, ty.valtype_cd, present
  from
  (
    select dx_yr, eav.naaccrId, count(*) present
    from with_yr eav
    group by dx_yr, eav.naaccrId
  ) agg
  join tumor_item_type ty on ty.naaccrId = agg.naaccrId
)
,
-- break down nominals by value
by_val as (
  select by_item.dx_yr, by_item.naaccrId, by_item.naaccrNum, by_item.present,
         by_item.valtype_cd, eav.value, count(*) freq
  from with_yr eav
  join by_item_yr by_item on eav.naaccrId = by_item.naaccrId and eav.dx_yr = by_item.dx_yr
  where by_item.valtype_cd = '@'
  group by by_item.dx_yr, by_item.naaccrId, by_item.naaccrNum, by_item.present, by_item.valtype_cd, eav.value
)
/*
,
-- TODO: parse dates
event as (
  select tumorid as case_index, eav.naaccrNum
       , date(substr(value, 1, 4) || '-' || substr(value, 5, 2) || '-' || substr(value, 7, 2)) as t
  from tumors_eav eav
  join tumor_item_type by_item on eav.naaccrNum = by_item.naaccrNum
  where by_item.valtype_cd = 'D'
)
,
-- pick out reference date variable: date of diagnosis
dxty as (
  select *
  from by_item
  where itemname = 'Date of Diagnosis')
,
-- pick out the reference event for each case
e0 as (
  select *
  from event
  where event.naaccrNum = (select naaccrNum from dxty)
)
,
-- normalize other events to the reference event
e2 as (
  select e0.naaccrNum, julianday(current_date) - julianday(e0.t) mag
  from e0
  union all
  select e.naaccrNum, julianday(e.t) - julianday(e0.t) mag
  from event e
  join e0
    on e0.case_index = e.case_index
   and e0.naaccrNum <> e.naaccrNum
)
,
-- assuming normal distribution, characterize continuous data
stats as (
  select naaccrNum, count(mag) present, avg(mag) mean, stddev(mag) sd
  from e2
  group by naaccrNum
)
*/

-- For nominal data, save the frequency of each value
select by_val.dx_yr, by_val.naaccrId, by_val.naaccrNum, by_val.valtype_cd
     , cast(null as float) mean, cast(null as float) sd
     , by_val.value, by_val.freq
     , by_val.present
     , cases.tumor_qty
from by_val
join cases on cases.dx_yr = by_val.dx_yr

/* TODO
union all

-- For continuous data, save mean, stddev
select stats.naaccrNum, by_item.valtype_cd
     , mean, sd
     , null value, null freq, null pct, stats.present, cases.tumor_qty
from stats
join by_item on stats.naaccrNum = by_item.naaccrNum
cross join cases
*/

;

create or replace temporary view data_char_naaccr_nom as
select s.sectionId, rl.section, nom.*
from data_agg_naaccr nom
join record_layout rl
  on rl.`naaccr-item-num` = nom.naaccrNum
join section s
  on s.section = rl.section
;

create or replace temporary view data_char_naaccr as
select d.dx_yr, ty.sectionid, ty.section, ty.naaccrNum, ty.naaccrId, ty.valtype_cd
     , freq, present, tumor_qty
     , round(mean / 365.25, 2) mean_yr, round(sd / 365.25, 2) sd_yr
     , mean                           , sd
     , value
from tumor_item_type ty
join data_agg_naaccr d on d.NaaccrNum = ty.NaaccrNum
-- order by ty.sectionid, ty.NaaccrNum, value
;


create or replace temporary view nominal_cdf as
-- Compute cumulative distribution function for each value of each nominal item.
select dx_yr, naaccrNum, naaccrId, value, freq
     , sum(freq)
       over(partition by dx_yr, naaccrNum, naaccrId
            order by value
            rows between unbounded preceding and current row)
            as cum_freq
from data_agg_naaccr
;

create or replace temporary view simulated_case_year as
with by_yr as (
select distinct dx_yr, tumor_qty
from data_agg_naaccr
where dx_yr >= 2004  -- ISSUE: parameterize registry reference year?
),
all_yr as (
select sum(tumor_qty) as qty
from by_yr
),
yr_cum as (
select dx_yr
     , tumor_qty
     , sum(tumor_qty)
       over(partition by 1
            order by dx_yr
            rows between unbounded preceding and current row)
            as qty_cum
from by_yr
),
pick as (
select case_index, cast(rand() * all_yr.qty as int) as x
from simulated_entity
cross join all_yr
)
select pick.*, yr_cum.*
from pick
join yr_cum on pick.x >= yr_cum.qty_cum - yr_cum.tumor_qty
and pick.x < yr_cum.qty_cum
;


create or replace temporary view simulated_naaccr_nom as
with
by_item as (
  select dx_yr, sectionId, naaccrNum, naaccrId, valtype_cd, mean, sd
       , present, tumor_qty
       , sum(freq) + (tumor_qty - present) as denominator
  from data_char_naaccr d
  group by dx_yr, sectionId, naaccrNum, naaccrId, valtype_cd, mean, sd, present, tumor_qty
)
,
-- for each item of each case, pick a uniformly random number
ea as (
  select cy.case_index, cy.dx_yr, sectionId, by_item.naaccrNum, by_item.naaccrId, by_item.valtype_cd
       , by_item.present, by_item.tumor_qty
       , rand() * denominator as x
  from simulated_case_year cy
  join by_item on cy.dx_yr = by_item.dx_yr
)
select ea.case_index, sectionId, ea.dx_yr, ea.naaccrNum, ea.naaccrId, by_val.value
     , ea.x, by_val.cum_freq
from ea
-- this join will not match when x corresponds to a null (i.e. tumor_qty - present)
join nominal_cdf by_val
  on by_val.naaccrNum = ea.naaccrNum and by_val.dx_yr = ea.dx_yr
where ea.x >= by_val.cum_freq - by_val.freq
  and ea.x < by_val.cum_freq
;


create or replace temporary view simulated_naaccr as
with
by_item as (
  select distinct naaccrNum, naaccrId, valtype_cd, mean, sd, present, tumor_qty
  from data_char_naaccr d
)
,
-- for each item of each case, pick a uniformly random percentage and a normally distributed magnitude
ea as (
  select e.case_index, by_item.naaccrNum, by_item.valtype_cd
       , by_item.present, by_item.tumor_qty
       , (e.case_index * 1017 + by_item.naaccrNum) % 100 as x  -- kludge; random() and CTEs don't work
       , ((e.case_index * 1017 + by_item.naaccrNum) % 100) / 100.0 * sd + mean as mag
  from simulated_entity e
  cross join by_item
)
,
-- compute reference event date
-- TODO: consider distributing these uniformly rather than normally
e0 as (
  select case_index, naaccrNum, tumor_qty, date(current_date, '-' || mag || ' days') t
       , ea.x, ea.mag
  from ea
  where naaccrNum = 390 -- Date of Diagnosis
)
,
-- compute dates of other events, with the same percentage of nulls
e2 as (
  select ea.case_index, ea.naaccrNum, ea.tumor_qty
       , case when ea.x > ea.present / e0.tumor_qty * 100
         then date(e0.t, ea.mag || ' days')
         else null
         end t
       , ea.x, ea.mag
  from ea
  join e0 on e0.case_index = ea.case_index
  where e0.naaccrNum <> ea.naaccrNum
  and ea.valtype_cd = 'D'
)
,
event as (
  select * from e0
  union all
  select * from e2
)

-- Correlate the random percentage with the relevant value
select ea.case_index, ea.naaccrNum, by_val.value
     , ea.x, by_val.cdf, by_val.pct
from ea
join nominal_cdf by_val
  on by_val.naaccrNum = ea.naaccrNum
where ea.x >= by_val.cdf
  and ea.x < by_val.cdf + by_val.pct

union all

-- Convert dates to strings
select event.case_index, event.naaccrNum
     , substr(event.t, 1, 4) ||
       substr(event.t, 5, 2) ||
       substr(event.t, 7, 2) value
     , x, null, mag
from event
;

/* Eyeball simulated_naaccr:

select d.case_index, ty.sectionid, ty.section, ty.naaccrNum, ty.itemname, ty.valtype_cd, d.value
from simulated_naaccr d
join tumor_item_type ty on ty.naaccrNum = d.naaccrNum
order by d.case_index, ty.sectionid, ty.naaccrNum;
*/

