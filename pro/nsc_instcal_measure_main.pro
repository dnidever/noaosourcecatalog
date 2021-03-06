;+
;
; NSC_INSTCAL_MEASURE_MAIN
;
; This runs SExtractor on the DECam InstCal images.
; This is a wrapper around nsc_instcal_measure.py which runs
; on one individual exposure.
;
; INPUTS:
;  version   The version name, e.g. 'v3'.
;  =hosts    Array of hosts to run.  The default is gp06-gp09,hulk and thing.
;  =redo     Rerun on exposures that were previously processed.
;  =nmulti   The number of simultaneously jobs to run. Default is 30.
;  =maxjobs  The maximum number of exposures to attempt to process.
;              The default is 40,000.
;  /silent   Don't print much to the screen.
;  /unlock   Ignore the lock files.
;
; OUTPUTS:
;  A log "journal" file is put in ROOTDIR+users/dnidever/nsc/instcal/v#/logs/
;  as well as a structure with information on the jobs that were run.
;  The individual catalogs are put in ROOTDIR+users/dnidever/nsc/instcal/v#/NIGHT/EXPOSURENAME/.
;
; USAGE:
;  IDL>nsc_instcal_measure_main,'v3'
;
; By D.Nidever  Feb 2017
;-

pro nsc_instcal_measure_main,version,hosts=hosts,redo=redo,nmulti=nmulti,maxjobs=maxjobs,silent=silent,dolock=dolock,unlock=unlock

if n_elements(version) eq 0 then begin
  print,'Syntax - nsc_instcal_measure_main,version,hosts=hosts,redo=redo,nmulti=nmulti,maxjobs=maxjobs,silent=silent,dolock=dolock,unlock=unlock'
  return
endif

; Main NOAO DECam source catalog
NSC_ROOTDIRS,dldir,mssdir,localdir,host
hostname = first_el(strsplit(host,'.',/extract))
if n_elements(maxjobs) eq 0 then maxjobs=48300L
if n_elements(nmulti) eq 0 then nmulti=30
dir = dldir+'users/dnidever/nsc/instcal/'+version+'/'
tmpdir = localdir+'dnidever/nsc/instcal/'+version+'/tmp/'
if file_test(tmpdir,/directory) eq 0 then file_mkdir,tmpdir
subdirs = ['logs','c4d','k4m','ksb']
for i=0,n_elements(subdirs)-1 do if file_test(dir+subdirs[i],/directory) eq 0 then file_mkdir,dir+subdirs[i]
;; Hosts
if n_elements(hosts) eq 0 then hosts = ['gp06','gp07','gp08','gp09','hulk','thing']
if total(hosts eq hostname) eq 0 then begin
  print,'Current HOST='+hostname+' not in list of HOSTS = [ '+strjoin(hosts,', ')+' ] '
  return
endif

t0 = systime(1)

; Log file
;------------------
; format is nsc_main_laf.DATETIME.log
jd = systime(/julian)
caldat,jd,month,day,year,hour,minute,second
smonth = strtrim(month,2)
if month lt 10 then smonth = '0'+smonth
sday = strtrim(day,2)
if day lt 10 then sday = '0'+sday
syear = strmid(strtrim(year,2),2,2)
shour = strtrim(hour,2)
if hour lt 10 then shour='0'+shour
sminute = strtrim(minute,2)
if minute lt 10 then sminute='0'+sminute
ssecond = strtrim(round(second),2)
if second lt 10 then ssecond='0'+ssecond
logtime = smonth+sday+syear+shour+sminute+ssecond
logfile = dir+'logs/nsc_instcal_measure_main.'+logtime+'.log'
JOURNAL,logfile

print, "Running SExtractor on the DECam/Mosaic3/Bok InstCal Images"

; Loading the lists
;str = MRDFITS(dir+'decam_instcal_list.fits',1)
list1 = MRDFITS(dir+'/lists/decam_instcal_list.fits.gz',1)
list2 = MRDFITS(dir+'/lists/mosaic3_instcal_list.fits.gz',1)
list3 = MRDFITS(dir+'/lists/bok90prime_instcal_list.fits.gz',1)
str = [list1,list2,list3]
undefine,list1,list2,list3
nstr = n_elements(str)
str.fluxfile = strtrim(str.fluxfile,2)
str.maskfile = strtrim(str.maskfile,2)
str.wtfile = strtrim(str.wtfile,2)
print,strtrim(nstr,2),' InstCal images'

;; Putting them in RANDOM but REPEATABLE order
seed = 1
print,'RANDOMIZING WITH SEED=1'
si = sort(randomu(seed,n_elements(str)))
str = str[si]

gdexp = lindgen(nstr)
ngdexp = nstr

; Check the exposures
print,'Checking on the exposures'
expstr = replicate({instrument:'',fluxfile:'',wtfile:'',maskfile:'',allexist:0,outfile:'',done:0,locked:0,torun:0,cmd:'',cmddir:'',submitted:0},ngdexp)
for i=0,ngdexp-1 do begin
  if i mod 5000 eq 0 then print,i

  instrument = strtrim(str[gdexp[i]].instrument,2)
  fluxfile = strtrim(str[gdexp[i]].fluxfile,2)
  wtfile = strtrim(str[gdexp[i]].wtfile,2)
  maskfile = strtrim(str[gdexp[i]].maskfile,2)
  ;wtfile = repstr(fluxfile,'ooi','oow')
  ;maskfile = repstr(fluxfile,'ooi','ood')
  base = file_basename(fluxfile)

  ; Change the root directory name
  ;  /net/mss1/blah/blah/
  fluxfile = mssdir+strmid(fluxfile,10)
  wtfile = mssdir+strmid(wtfile,10)
  maskfile = mssdir+strmid(maskfile,10)
  expstr[i].instrument = instrument
  expstr[i].fluxfile = fluxfile
  expstr[i].wtfile = wtfile
  expstr[i].maskfile = maskfile

  ; Check if the output already exists.
  dateobs = str[gdexp[i]].date_obs
  night = strmid(dateobs,0,4)+strmid(dateobs,5,2)+strmid(dateobs,8,2)
  baseroot = file_basename(base,'.fits.fz')
  ;outfile = dldir+'users/dnidever/decamcatalog/instcal/'+night+'/'+baseroot+'/'+baseroot+'_'+strtrim(1,2)+'.fits'
  outfile = dir+instrument+'/'+night+'/'+baseroot+'/'+baseroot+'_'+strtrim(1,2)+'.fits'
  expstr[i].outfile = outfile

  ; Do all three files exist?
  ;if file_test(fluxfile) eq 1 and file_test(wtfile) eq 1 and file_test(maskfile) eq 1 then expstr[i].allexist=1
  expstr[i].allexist = 1    ; THIS TAKES TOO LONG!!!
  ; Does the output file exist
  ;if file_test(outfile) eq 1 or file_test(outfile+'.gz') eq 1 then expstr[i].done = 1
  ;expstr[i].done = 0

  ; Not all three files exist
  if expstr[i].allexist eq 0 then begin
    if not keyword_set(silent) then print,'Not all three flux/wt/mask files found for ',fluxfile
    goto,BOMB
  endif

  ; Already done
  if (expstr[i].done eq 1) and not keyword_set(redo) then begin
    if not keyword_set(silent) then print,outfile,' EXISTS and /redo NOT set'
    goto,BOMB
  endif

  ;lock = djs_lockfile(outfile)
  lockfile = outfile+'.lock'
  ;testlock = file_test(lockfile)  
  testlock = 0

  ; No lock file
  ;if lock eq 1 or keyword_set(unlock) then begin
  if (testlock eq 0 or keyword_set(unlock)) then begin
    ;dum = djs_lockfile(outfile)  ; this is slow
    ;if file_test(file_dirname(outfile),/directory) eq 0 then file_mkdir,file_dirname(outfile)  ; make directory
    ;if testlock eq 0 then touchzero,outfile+'.lock'  ; this is fast
    expstr[i].cmd = '/home/dnidever/projects/noaosourcecatalog/python/nsc_instcal_measure.py '+fluxfile+' '+wtfile+' '+maskfile+' '+version
    expstr[i].cmddir = tmpdir
    expstr[i].torun = 1
  ; Lock file exists
  endif else begin
    expstr[i].locked = 1
    expstr[i].torun = 0
    if not keyword_set(silent) then print,'Lock file exists ',outfile+'.lock'
  endelse
  BOMB:
endfor

;; Parcel out the jobs
nhosts = n_elements(hosts)
torun = where(expstr.torun eq 1,nalltorun)
nperhost = nalltorun/nhosts
for i=0,nhosts-1 do $
  if stregex(host,hosts[i],/boolean) eq 1 then torun=torun[i*nperhost:(i+1)*nperhost-1]
ntorun = n_elements(torun)

if ntorun eq 0 then begin
  print,'No exposures to process.'
  return
endif

; Pick the jobs to run
; MAXJOBS
if ntorun gt maxjobs then begin
  print,'More jobs than MAXJOBS.  Cutting down to ',strtrim(maxjobs,2),' jobs'
  expstr[torun[0:maxjobs-1]].submitted = 1
endif else expstr[torun].submitted = 1
tosubmit = where(expstr.submitted eq 1,ntosubmit)
print,strtrim(ntosubmit,2),' jobs to submit'
cmd = expstr[tosubmit].cmd
cmddir = expstr[tosubmit].cmddir

; Lock the files that will be submitted
if keyword_set(dolock) then begin
  print,'Locking files to be submitted'
  for i=0,ntosubmit-1 do begin
    outfile = expstr[tosubmit[i]].outfile
    if file_test(file_dirname(outfile),/directory) eq 0 then file_mkdir,file_dirname(outfile)  ; make directory
    lockfile = outfile+'.lock'
    testlock = file_test(lockfile)
    if testlock eq 0 then touchzero,outfile+'.lock'  ; this is fast
    expstr[tosubmit[i]].locked = 1
  endfor
endif ; /dolock

; Saving the structure of jobs to run
runfile = dir+'lists/nsc_instcal_measure_main.'+hostname+'.'+logtime+'_run.fits'
print,'Writing running information to ',runfile
MWRFITS,expstr,runfile,/create

; Run PBS_DAEMON
stop
a = '' & read,a,prompt='Press RETURN to start'
PBS_DAEMON,cmd,cmddir,jobs=jobs,/hyperthread,prefix='nscmeas',wait=5,nmulti=nmulti

; Unlocking files
if keyword_set(dolock) then begin
  print,'Unlocking processed files'
  file_delete,expstr[tosubmit].outfile+'.lock',/allow,/quiet
endif

print,'dt=',stringize(systime(1)-t0,ndec=2),' sec'

; End logfile
;------------
JOURNAL

stop

end
