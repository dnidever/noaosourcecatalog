pro smash_matched_catalogs_v3

; Get calibrated fields with full ugriz
; and not in the LMC/SMC main bodies

rootdir = smashred_rootdir()
info = mrdfits(rootdir+'cp/red/photred/catalogs/final/v6/check_calibrated_v6.fits',1)
;restore,'/data/smash/cp/red/photred/catalogs/pro/check_calibrated.dat'
gd = where(info.calflag eq 2 and info.nuchips gt 0 and long(strmid(info.field,5)) gt 60,ngd)
fields = strtrim(info[gd].field,2)
nfields = n_elements(fields)

catdir = rootdir+'cp/red/photred/catalogs/final/v6/'
gaiadir = rootdir+'cp/red/photred/gaia/'
galexdir = rootdir+'cp/red/photred/galex/'
;fields = ['Field101','Field110','Field134']
;nfields = n_elements(fields)

filters = ['u','g','r','i','z']
nfilters = n_elements(filters)

; Load the photometric fields and gaia data
undefine,mobj,mgaia
fieldstr = replicate({field:'',fieldid:0,nmatch:0L,ucoef:dblarr(5),urms:99.99,ubin:fltarr(31),gcoef:dblarr(4),grms:99.99,$
                      gbin:fltarr(31),rcoef:dblarr(4),rrms:99.99,rbin:fltarr(31),icoef:dblarr(4),irms:99.99,ibin:fltarr(31),$
                      zcoef:dblarr(5),zrms:99.99,zbin:fltarr(31)},nfields)
ftags = tag_names(fieldstr)
;restore,'/dl1/users/dnidever/nsc/smash_matched_catalog_v3.dat'
;for i=68,nfields-1 do begin
for i=0,nfields-1 do begin
  print,strtrim(i+1,2),'/',strtrim(nfields,2),' ',fields[i]
  info1 = info[gd[i]]

  ref = GETREFDATA('c4d-u',info1.ra,info1.dec,1.3)
  gdref = where(ref.gmag lt 50 and ref.jmag lt 50 and ref.nuv lt 50,ngdref)
  if ngdref eq 0 then begin
     print,'No good sources'
     goto,BOMB
  endif

  obj = mrdfits(catdir+fields[i]+'_combined_allobj.fits.gz',1)
  obj.id = strtrim(obj.id,2)
  otags = tag_names(obj)

  ; Now crossmatch with reference catalog
  srcmatch,obj.ra,obj.dec,ref.ra,ref.dec,0.5,ind1,ind2,/sph,count=nmatch
  print,strtrim(nmatch,2),' matches'
  if nmatch eq 0 then begin
    print,'No matches to reference catalog'
    goto,BOMB
  endif
  obj = obj[ind1]
  ref = ref[ind2]

  ; ONLY KEEP OJECTS WITH GALEX, 2MASS AND GAIA MATCHES
  ;gdkeep = where(ref.jmag lt 50 and ref.gmag lt 50 and ref.nuv lt 50,ngdkeep)
  ;print,strtrim(ngdkeep,2),' final sources with SMASH, Galex, 2MASS and Gaia matches'
  gdkeep = where(ref.jmag lt 50 and ref.gmag lt 50,ngdkeep)
  print,strtrim(ngdkeep,2),' final sources with SMASH, 2MASS and Gaia matches'
  if ngdkeep eq 0 then goto,BOMB
  obj = obj[gdkeep]
  ref = ref[gdkeep]

  ; Convert to common obj schema without indices
  ;  gaia too
  schema_obj = {id:'',fieldid:0,ra:0.d0,dec:0.0d0,u:99.99,uerr:9.99,g:99.99,gerr:9.99,r:99.99,rerr:9.99,$
                i:99.99,ierr:9.99,z:99.99,zerr:9.99,chi:99.99,sharp:99.99,flag:0,prob:99.99,ebv:99.99,$
                gaia_source:0L,gaia_gmag:99.99,gaia_gerr:9.99,gaia_bp:99.99,gaia_bperr:9.99,gaia_rp:99.99,$
                gaia_rperr:9.99,tmass_jmag:99.99,tmass_jerr:9.99,$
                tmass_kmag:99.99,tmass_kerr:9.99,tmass_qflg:'',$
                galex_nuv:99.99,galex_nuverr:9.99,ejk:0.0,ext_type:0}
  newobj = replicate(schema_obj,ngdkeep)
  struct_assign,obj,newobj
  newobj.fieldid = long(strmid(fields[i],5))
  struct_assign,ref,newobj,/nozero
  newobj.gaia_source = ref.source
  newobj.gaia_gmag = ref.gmag
  newobj.gaia_gerr = ref.e_gmag
  newobj.gaia_bp = ref.bp
  newobj.gaia_bperr = ref.e_bp
  newobj.gaia_rp = ref.rp
  newobj.gaia_rperr = ref.e_rp
  ;gmagerr = 2.5*alog10(1.0+ref.e_fg/ref.fg)
  ;newobj.gaia_gerr = gmagerr
  newobj.tmass_jmag = ref.jmag
  newobj.tmass_jerr = ref.e_jmag
  newobj.tmass_kmag = ref.kmag
  newobj.tmass_kerr = ref.e_kmag
  newobj.tmass_qflg = ref.qflg
  newobj.galex_nuv = ref.nuv
  newobj.galex_nuverr = ref.e_nuv
  newobj.ejk = ref.ejk
  newobj.ext_type = ref.ext_type

  fieldstr[i].field = fields[i]
  fieldstr[i].fieldid = long(strmid(fields[i],5))
  fieldstr[i].nmatch = ngdkeep

  ;; Initiate MOBJ
  if n_elements(mobj) eq 0 then begin
    mobj = replicate(schema_obj,2e7)
    nmobj = n_elements(mobj)
    cnt = 0LL
  endif
  ;; Add new elements to MOBJ
  if nmobj lt cnt+ngdkeep then begin
    print,'Adding new elements'
    old = mobj
    mobj = replicate(schema_obj,nmobj+1e6)
    mobj[0:nmobj-1] = old
    nmobj = n_elements(mobj)
    undefine,old
  endif
  ;; Stuff in new data
  mobj[cnt:cnt+ngdkeep-1] = newobj
  cnt += ngdkeep

  ;push,mobj,newobj

  BOMB:

  ;stop
endfor
mobj = mobj[0:cnt-1] ; trim extra elements

stop

;; RMS in the binned values
;urms = mad(fieldstr.ubin,dim=2)  ; ~5%
;grms = mad(fieldstr.gbin,dim=2)  ; ~2-5%
;rrms = mad(fieldstr.rbin,dim=2)  ; ~1%
;irms = mad(fieldstr.ibin,dim=2)  ; ~1%
;zrms = mad(fieldstr.zbin,dim=2)  ; ~1.5%

;save,fieldstr,mobj,file='/dl1/users/dnidever/nsc/smash_matched_catalog_v3.dat'
stop


end
