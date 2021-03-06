/** naaccr_txform -- transform NAACCR data to fit i2b2 star schema

Copyright (c) 2012-2015 University of Kansas Medical Center
part of the HERON* open source codebase; see NOTICE file for license details.
* http://informatics.kumc.edu/work/wiki/HERON

*/

-- test that we're in the KUMC sid with the NAACCR data
-- note mis-spelling of schema name: naacr
select "Accession Number--Hosp" from naacr.extract where 1=0;
select itemnbr from naacr.extract_eav where 1=0;
-- check for curated data
select name from seer_site_terms@deid where 1=0;

-- check for metadata tables
select * from naacr.t_item where 1=0;

alter session set NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI';

whenever sqlerror continue;
--Inside "continue" clause in case index is not there
drop index naacr.patient_id_idx;
drop index naacr.case_idx;

alter table naacr.extract add (case_index integer);  -- in case old naaccr_extract.sql was used

whenever sqlerror exit;

create index naacr.patient_id_idx on naacr.extract (
  "Patient ID Number");

create unique index naacr.case_idx on naacr.extract (
  case_index);


/* Item names are unique, right? */
select case when count(*) = 0 then 1 else 0 end as test_item_name_uniqueness
from (
select count(*), "ItemName"
from naacr.t_item ni
group by "ItemName"
having count(*) > 1
);


/* Race analysis/sanity check: How many of each?
 odd: no codecrp for 16, 17 */
select count(*), ne."Race 1", nc.codedcrp
from naacr.extract ne
join naacr.t_code nc
  on ne."Race 1" = nc.codenbr
join naacr.t_item ni
  on ni."ItemID" = nc.itemid
where ni."ItemName" = 'Race 1'
group by ne."Race 1", nc.codedcrp
order by 1 desc
;


/* Grade: how many of each kind? */
select count(*), ne."Grade", codedcrp
from naacr.extract ne
left join (
 select nc.codenbr, nc.codedcrp
 from naacr.t_code nc
 join naacr.t_item ni
   on nc.itemid = ni."ItemID" 
   where ni."ItemName" = 'Grade') nc
on ne."Grade" = nc.codenbr
group by ne."Grade", codedcrp
order by 1 desc
;


/********
 * "the big flat approach"

TODO: ISSUE: There are lots of codes for lack of information, e.g.
  - Grade/differentiation unknown, not stated, or not applicable
  - No further race documented
  - Unknown whether Spanish or not
  - Insurance status unknown
Do we want to record these as facts?

-- tricky: Cause of Death. ICD7-10 codes.

 */


/*****
 * Date parsing. Ugh.

Please excuse the copy-and-paste coding here; a p-sql function would
probably let us factor out the redundancy but we haven't crossed into
that territory yet.

 p. 97:
 "Below are the common formats to handle the situation where only
  certain components of date are known.
  YYYYMMDD - when complete date is known and valid
  YYYYMM - when year and month are known and valid, and day is unknown
  YYYY - when year is known and valid, and month and day are unknown
  Blank - when no known date applies"

But we also see wierdness such as '    2009' and '19719999'; see
test cases below.

In Date of Last Contact, we've also seen 19919999
*/
select itemname,  value
     , case
       when value in ('00000000', '99999999', '99990')
       then null
       when regexp_like(value, '^(17|18|19|20|21|22)[0-9]{2}(01|02|03|04|05|06|07|08|09|10|11|12)[0-3][0-9]$')
       then to_date(value, 'YYYYMMDD')
       when regexp_like(value, '^(01|02|03|04|05|06|07|08|09|10|11|12)[0-3][0-9](17|18|19|20|21|22)[0-9]{2}$')
       then to_date(value, 'MMDDYYYY')
       when regexp_like(value, '^[1-2][0-9]{3}(01|02|03|04|05|06|07|08|09|10|11|12)$')
       then to_date(value, 'YYYYMM')
       when regexp_like(value, '^[1-2][0-9]{3}$')
       then to_date(value, 'YYYY')
       end start_date
from (
select 'normal' as itemname, '19700101' as value from dual
union all
select 'no day' as itemname, '197001' as value from dual
union all
select 'no month' as itemname, '1970' as value from dual
union all
select 'leading space' as itemname, '    1970' as value from dual
union all
select 'no month, variation' as itemname, '19709999' as value from dual
union all
select 'all 9s' as itemname, '99999999' as value from dual
union all
select 'all 0s' as itemname, '00000000' as value from dual
union all
select 'almost all 9s' as itemname, '99990' as value from dual
union all
select 'inscruitable', '12001024' from dual
)
/* Hunt down "not a valid month"
select min(to_date(ne."Date of Last Contact", 'yyyymmdd'))
from (
  select * from (
  select rownum i, "Date of Last Contact", substr("Date of Last Contact", 5, 2) mm
  from naacr.extract
  ) where i > 960 and i < 970) ne;
*/
;

create table t_item as
select dd.item as ItemNbr
     , dd.name as ItemName
     , dd.Format
     , dd.allow_value as AllowValue
     , dd.length as FieldLength
     , s.sectionid as SectionID
from ddict.data_descriptor dd
join ddict.record_layout rl on rl.item = dd.item
join section s on s.section = rl.section
;


create table tumor_item_type as
select ns.sectionid
     , ns.section
     , ni."ItemNbr" ItemNbr
     , ni."Format"
     , ni."AllowValue"
     , ni.valtype_cd
     , ni."ItemName" as ItemName
from (
select case -- Determine valtype_cd, including '_i' PHI flag (see i2b2_facts_deid.sql)
         when ni."ItemName" like 'Reserved%' then null
         when ni."FieldLength" is null then null

         when ni."ItemName" =  'Rad--Regional Dose: CGY' then 'N'
         when ni."ItemName" like '%Tumor Size%' then 'N'
         when ni."ItemName" like '%ICD-O-1' then '@'
         when ni."AllowValue" like 'Valid ICD-7, ICD-8, ICD-9%' then '@'
         when ni."ItemName" like 'Comorbid/Complication%' then '@'

         when ni."ItemName" = 'Patient ID Number' then 'Ti'
         when ni."ItemName" in ('Latitude', 'Longitude') then 'Ni'         
         when ni."AllowValue" = 'City name or UNKNOWN' then 'Ti'
         -- TODO: handle YYYYMMDDhhmmss as date?
         when ni."Format" = 'YYYYMMDD' then 'D'
         when ni."ItemName" like 'Text--%' then 'Ti'
         when ni."ItemName" like 'Age%' then 'Ni'
         when ni."AllowValue" like 'Census Tract Codes 00%' then 'Ti'
         when ni."AllowValue" like '10-digit%' and ni."ItemName" not like '%ID' then 'Ni'
         when ni."Format" like 'Numbers or upper case letters%' then 'Ti'
 
          -- fields 3 characters or smaller are codes that aren't PHI
         when "FieldLength" <= 3 then '@'
          -- In certain sections, fields up to 5 characters are non-PHI codes
         when "FieldLength" <= 5 and ni."SectionID" in (
  1 -- Cancer Identification
 , 2 -- Demographic
-- , 3 -- Edit Overrides/Conversion History/System Admin
 , 4 -- Follow-up/Recurrence/Death
-- , 5 -- Hospital-Confidential
 , 6 -- Hospital-Specific
-- , 7 -- Other-Confidential
-- , 8 -- Patient-Confidential
-- , 9 -- Record ID
-- , 10 -- Special Use
 , 11 -- Stage/Prognostic Factors
     -- TODO: for long lists of numeric codes, find metadata
     -- and chunking strategy
     -- TODO: consider normalizing complication 1, complication 2, ...
-- , 12 -- Text-Diagnosis
-- , 13 -- Text-Miscellaneous
-- , 14 -- Text-Treatment
, 15 -- Treatment-1st Course
, 16 -- Treatment-Subsequent & Other
, 17 -- Pathology
         ) then '@'
         when ni."Format" like '%zero filled' then 'Ni'
         else 'Ti'
       end valtype_cd
     , ni.*
from t_item ni
) ni
join section ns on ns.sectionid = ni."SectionID"
and ni.valtype_cd is not null
;

insert into etl_test_values (test_domain, test_name, test_value, result_id, result_date, detail_num_1, detail_char_1)
select 'Cancer Cases' test_domain, 'rx_summary_item_types' test_name
     , case when ty.itemnbr is null then 0 else 1 end test_value
     , sq_result_id.nextval result_id
     , sysdate result_date
     , rx.itemnbr, rx.itemname
from
(
select 1640 itemnbr, 'RX Summ--Surgery Type' itemname from dual union all
select 1290,         'RX Summ--Surg Prim Site' from dual union all
select 1292,         'RX Summ--Scope Reg LN Sur' from dual union all
select 1294,         'RX Summ--Surg Oth Reg/Dis' from dual union all          
select 1296,         'RX Summ--Reg LN Examined' from dual union all
select 1330,         'RX Summ--Reconstruct 1st' from dual union all      
select 1340,         'Reason for No Surgery' from dual union all 
select 1360,         'RX Summ--Radiation' from dual union all
select 1370,         'RX Summ--Rad to CNS' from dual union all
select 1380,         'RX Summ--Surg/Rad Seq' from dual

union all  -- not related to RX, but has the same test structure
select 0230,         'Age at Diagnosis' from dual union all
select 0560,         'Sequence Number-Hospital' from dual
) rx
left join tumor_item_type ty
  on ty.itemnbr = rx.itemnbr
;

/* This is the main big flat view. */
     -- TODO: for long lists of numeric codes, find metadata
     -- and chunking strategy
     -- TODO: consider normalizing complication 1, complication 2, ...
create or replace view tumor_item_value as
select case_index
     , ns.sectionid
     , ne.ItemNbr
     , ni.valtype_cd
     , case
         when valtype_cd like 'T%' then value
         when valtype_cd like 'D%'
          and regexp_like(value, '^(17|18|19|20|21|22)[0-9]{2}(01|02|03|04|05|06|07|08|09|10|11|12)[0-3][0-9]$')
         then
           substr(value, 1, 4) || '-' || substr(value, 5, 2) || '-' || substr(value, 7, 2)
         else null
       end tval_char
     , case
         when valtype_cd like 'N%' then to_number(ne.value)
         else null
       end nval_num
     , case when valtype_cd like 'D%' 
            then coalesce( to_date_noex(value, 'YYYYMMDD')
                         , to_date_noex(value, 'MMDDYYYY')
                         , to_date_noex(value, 'YYYYMM')
                         , to_date_noex(value, 'YYYY'))
            else null end as start_date
     , 'NAACCR|' || ne.itemnbr || ':' || (
         case when ni.valtype_cd like '@%' then value
         else null end) as concept_cd
     , case when ni.valtype_cd like '@%' then value
       else null end as codenbr
     , ns.section
     , ni.ItemName
from naacr.extract_eav ne
join tumor_item_type ni
  on ne.itemnbr = ni.ItemNbr
join NAACR.t_section ns on ns.sectionid = ni.SectionID
where ne.value is not null
and ni.valtype_cd is not null
;
/* eyeball it:

select * from tumor_item_value tiv
where "Accession Number--Hosp" like '%555';

How many different concept codes are there, excluding comorbidities?

select distinct(concept_cd) from tumor_item_value tiv
where valtype_cd not like '_i'
and concept_cd not like 'NAACCR|31%';

~9000.

*/


/**
 * i2b2 style visit info
 */
create or replace view tumor_reg_visits as
select ne.case_index
       as encounter_ide
     , ne."Patient ID Number" as MRN
from naacr.extract ne
where ne."Accession Number--Hosp" is not null;



-- select * from tumor_reg_visits;
-- select count(*) from tumor_reg_visits;
-- 65576

/**
 * i2b2 style facts
 */
create or replace view tumor_reg_facts as
select MRN, encounter_ide
     , concept_cd, ItemName
     , '@' provider_id
     , start_date
     , '@' modifier_cd
     , 1 instance_num
     , valtype_cd
     , tval_char
     , nval_num
     , null as valueflag_cd
     , null as units_cd
     , start_date as end_date
     , '@' location_cd
     , to_date(null) as update_date
from (
select
  ne."Patient ID Number" as MRN,
  ne.case_index as encounter_ide,
  av.concept_cd,
  av.ItemName,
  av.valtype_cd, av.nval_num, av.tval_char,
  case
  when av.start_date is not null then av.start_date
  -- Use Date of Last Contact for Follow-up/Recurrence/Death
  when av.sectionid = 4
  then coalesce( to_date_noex(ne."Date of Last Contact", 'YYYYMMDD')
               , to_date_noex(ne."Date of Last Contact", 'MMDDYYYY')
               , to_date_noex(ne."Date of Last Contact", 'YYYYMM')
               , to_date_noex(ne."Date of Last Contact", 'YYYY'))
  -- Use Date of Diagnosis for everything else
  else coalesce( to_date_noex(ne."Date of Diagnosis", 'YYYYMMDD')
               , to_date_noex(ne."Date of Diagnosis", 'MMDDYYYY')
               , to_date_noex(ne."Date of Diagnosis", 'YYYYMM')
               , to_date_noex(ne."Date of Diagnosis", 'YYYY'))
  end as start_date
from naacr.extract ne
join (
select tiv.case_index
     , tiv.start_date
     , tiv.concept_cd
     , tiv.valtype_cd, tiv.nval_num, tiv.tval_char
     , tiv.ItemName
     , tiv.SectionId
from tumor_item_value tiv

) av
 on ne.case_index = av.case_index
/* TODO: figure out what's up with the 42 records with no Date of Diagnosis
and the ones with no date of last contact */
and ne."Accession Number--Hosp" is not null)
where start_date is not null;

-- eyeball it:
-- select * from tumor_reg_facts order by encounter_ide desc, start_date desc;


/* count facts by scheme

select count(*), scheme from(
select substr(f.concept_cd, 1, instr(f.concept_cd, ':')) scheme
from tumor_reg_facts f)
group by scheme
order by 1 desc;
*/
