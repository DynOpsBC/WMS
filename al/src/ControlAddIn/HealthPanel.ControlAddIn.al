controladdin "DOPSWHS Health Panel"
{
    // Depo Sağlık Paneli (Sorun Merkezi) — BC sayfası içine gömülü React
    // paketi (web/src/healthPanel, tek IIFE). Veri SetData ile JSON gelir;
    // düzeltme/gezinme olayları AL'de çalışır, sonra panel yenilenir.
    RequestedHeight = 760;
    MinimumHeight = 420;
    RequestedWidth = 1000;
    MinimumWidth = 360;
    VerticalStretch = true;
    HorizontalStretch = true;
    // Tek IIFE paket yalnız StartupScript olarak yüklenir (iki kez çalışmasın).
    StyleSheets = 'Resources/healthPanel.css';
    StartupScript = 'Resources/healthPanel.js';

    /// <summary>Panel verisi (DOPSWHS Health Detector.BuildJson).</summary>
    procedure SetData(Json: Text);
    /// <summary>Düzeltme sonucu: {"ok":bool,"message":text}.</summary>
    procedure NotifyResult(Json: Text);
    /// <summary>Tarama sürerken yükleniyor göstergesi.</summary>
    procedure SetBusy(Busy: Boolean);

    event ControlReady();
    event RequestRefresh(LocationFilter: Text);
    event FixIssue(EntryNo: Integer);
    event FixCategory(CategoryKey: Text);
    event ShowIssue(EntryNo: Integer; Target: Text);
}
