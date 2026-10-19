import os,subprocess,json,pathlib,datetime
BASE='https://api.businesscentral.dynamics.com/v2.0/3bbd610b-95e4-47b3-8b48-4f7caf717bc3/sand0309/api/'
COMPANY='752a7ff6-9946-f011-be59-002248d35589'
API=BASE+'dynops/warehouse/v2.0/companies('+COMPANY+')'
FIX=BASE+'dynops/sandboxTests/v1.0/companies('+COMPANY+')/productionFixtures('+COMPANY+')/Microsoft.NAV.'
OUT=pathlib.Path(os.environ.get('SANDBOX_TEST_OUTPUT','tmp/concurrency-sand0309'));OUT.mkdir(parents=True,exist_ok=True);history=[]
def call(method,url,body=None,expect=True,body2=None):
 assert '/sand0309/' in url
 args=['dotnet',os.environ['SANDBOX_HTTP_DLL'],method,url]
 if body is not None:
  p=OUT/'request.json';p.write_text(json.dumps(body));args.append(str(p))
 if body2 is not None:
  p=OUT/'request2.json';p.write_text(json.dumps(body2));args.append(str(p))
 r=subprocess.run(args,capture_output=True,text=True,timeout=210,env=os.environ.copy())
 history.append({'method':method,'url':url,'response':r.stdout,'returncode':r.returncode})
 (OUT/'results.json').write_text(json.dumps(history,ensure_ascii=False,indent=2))
 print(method,url.split('/')[-1],r.stdout[:500],flush=True)
 if expect: assert r.returncode==0,r.stdout+' '+r.stderr[-400:]
 if method=='CONCURRENT':return json.loads(r.stdout)
 return json.loads(r.stdout.split('\n',1)[1]) if r.stdout.split('\n',1)[1].strip() else None

def plan(rows,prepared):
 return [{'lineNo':r['lineNo'],'identity':'|'.join(str(r.get(k,'')) for k in ('no','itemNo','variantCode','locationCode','binCode','serialNo','unitOfMeasureCode')).upper(),'lotNo':r['lotNo'],'quantity':r['qtyToHandle'],'steps':[{'lpNo':'TARGET-PREP-LP' if prepared else ('PROD-LP-READY' if r['binCode']=='RAW' else 'SECOND-PREP-LP'),'binCode':r['binCode'],'lotNo':r['lotNo'],'serialNo':r['serialNo'],'baseQuantity':r['qtyToHandle']}]} for r in rows if r['actionType']=='Take']
try:
 for n in range(6):
  print('ROUND',n+1,flush=True)
  call('POST',FIX+'setupFixture',{})
  h=call('GET',API+"/picks('PROD-PICK-TEST')")
  rows=call('GET',API+"/pickLines?$filter=no%20eq%20%27PROD-PICK-TEST%27")['value']
  body={'userId':h['assignedUserId'],'targetBinCode':'STAGE','palletPlan':json.dumps(plan(rows,False))}
  replies=call('CONCURRENT',API+"/picks('PROD-PICK-TEST')/Microsoft.NAV.prepareProductionLPFor",body,body2=({**body,'userId':'PP-OTHER-OPERATOR'} if n>=3 else None))
  assert replies[0]['status']==204 and replies[1]['status']==(400 if n>=3 else 204)
  assert any(200<=r['status']<300 for r in replies)
  call('POST',FIX+'verifyPrepared',{})
  rows=call('GET',API+"/pickLines?$filter=no%20eq%20%27PROD-PICK-TEST%27")['value']
  body.update(targetBinCode='PROD',palletPlan=json.dumps(plan(rows,True)))
  replies=call('CONCURRENT',API+"/picks('PROD-PICK-TEST')/Microsoft.NAV.deliverProductionLPFor",body,body2=({**body,'userId':'PP-OTHER-OPERATOR'} if n>=3 else None))
  assert sum(200<=r['status']<300 for r in replies)==1
  call('POST',FIX+'verifyDelivered',{})
finally:
 call('POST',FIX+'cleanupFixture',{})
