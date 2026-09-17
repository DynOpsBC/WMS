# Python mirror of codeunit 72320 "DOPSWHS MTE Zpl Builder" (landscape-on-portrait) for Labelary previews.
from pathlib import Path

LW, LH = 812, 1218
CW, CH = 1218, 812
def enc(v): return v.replace('_','_5F').replace('^','_5E').replace('~','_7E').replace('>','_3E')
def fit(v, fw, maxw):
    n=len(v)
    if n==0: return fw
    if n*fw*55//100 <= maxw: return fw
    return max(12, maxw*100//(55*n))
def box(x,y,w,h,t): return f'^FO{LW-y-h},{x}^GB{h},{w},{t}^FS'
def line(x,y,w,t): return box(x,y,w,t,t)
def text(x,y,fh,fw,bw,al,v):
    if v=='': return ''
    a='C' if al==1 else 'L'; fw=fit(v,fw,bw)
    return f'^FO{LW-y-fh},{x}^A0R,{fh},{fw}^FH_^FB{bw},1,0,{a}^FD{enc(v)}^FS'
def cell(x,y,w,h,fh,fw,al,v): return box(x,y,w,h,2)+text(x+6,y+(h-fh)//2,fh,fw,w-12,al,v)
def decision_cell(y,h,v): return box(592,y,216,h,2)+text(598,y+10,28,26,204,1,v)
def row4(y,h,la,vb,lc,vd): return cell(24,y,272,h,26,24,1,la)+cell(296,y,296,h,26,22,1,vb)+cell(592,y,306,h,26,24,1,lc)+cell(898,y,296,h,26,22,1,vd)
def row2(y,h,la,v): return cell(24,y,272,h,26,24,1,la)+cell(296,y,898,h,26,22,1,v)
def rowl(y,h,la,v): return cell(24,y,272,h,24,22,1,la)+cell(296,y,296,h,24,20,1,v)
def qr(x,y,m,d): return f'^FO{LW-y-21*m},{x}^BQN,2,{m}^FH_^FDLA,{enc(d)}^FS'
UY=lambda v: v if v.strip() else 'U.Y'
d=dict(company='BS GROUP', itemno='AB.00002', cat='PRİMER AMBALAJ', name='BARDAK - CAM OPAK BORDO SİLİNDİR BASKISIZ 120 ML',
 inci='BADE NATURAL SWEET DREAMS İÇİN', vendor='RAPSODİ DEKOR SANAYİ A.Ş.', slot='', prod='', lot='A101663', exp='', qty='45 ADET',
 storage='ODA SIC. (15-25 °C)', rdate='12.06.2026', rno='107632', insp='DYNOPS', qcname='', qcdate='', doc='ET011', rev='01', revd='24.07.2026', qrd='LP000047')
z='^XA^CI28^PW%d^LL%d'%(LW,LH)
z+=box(24,24,1170,764,3)+Path(__file__).with_name('mte-bs-group-logo.zpl').read_text()+text(24,32,40,36,1170,1,'MADDE TANIMLAMA ETİKETİ')+line(24,78,1170,3)
z+=row4(78,43,'MADDE KODU',d['itemno'],'MADDE KATEGORİSİ',UY(d['cat']))+row2(121,43,'MADDE ADI',UY(d['name']))+row2(164,43,'INCI ADI',UY(d['inci']))+row2(207,43,'TEDARİKÇİ ADI',UY(d['vendor']))+row2(250,43,'TEDARİKÇİ LOTU',UY(d['slot']))
z+=row4(293,43,'ÜRETİM TARİHİ',UY(d['prod']),'LOT NO',UY(d['lot']))+row4(336,43,'SON KULLANMA TARİHİ',UY(d['exp']),'LP Miktar/Birim',d['qty'])
z+=rowl(379,42,'DEPOLAMA KOŞULU',UY(d['storage']))+rowl(421,43,'DEPO GİRİŞ TARİHİ',UY(d['rdate']))+rowl(464,42,'DEPO GİRİŞ NO.',UY(d['rno']))+rowl(506,49,'GİRİŞ YAPAN',UY(d['insp']))+cell(24,555,568,35,24,22,1,'KALİTE KONTROL ONAYI')+rowl(590,42,'KONTROL EDEN',UY(d['qcname']))+rowl(632,42,'TARİH',UY(d['qcdate']))+rowl(674,82,'İMZA','')
z+=decision_cell(379,125,'KABUL')+decision_cell(504,126,'RED')+decision_cell(630,126,'KARANTİNA')+box(808,379,386,377,2)+qr(896,433,10,d['qrd'])+text(808,661,40,36,386,1,d['qrd'])
z+=cell(24,756,568,32,22,20,0,'DOKÜMAN NO. / REVİZYON NO. / REVİZYON TARİHİ')+cell(592,756,602,32,22,20,1,UY(d['doc'])+' / '+UY(d['rev'])+' / '+UY(d['revd']))+'^XZ'
Path(__file__).with_name('mte-zpl-landscape-4x6.zpl').write_text(z, encoding='utf-8')
print(len(z),'bytes')
