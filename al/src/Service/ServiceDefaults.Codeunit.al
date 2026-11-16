codeunit 72101 "DOPSWHS Service Defaults"
{
    Permissions = tabledata "DOPSWHS Service Setup" = RIM,
        tabledata "Unit of Measure" = RI,
        tabledata "Repair Status" = RI,
        tabledata "Service Status Priority Setup" = RI,
        tabledata "Fault Area" = RI,
        tabledata "Symptom Code" = RI,
        tabledata "Fault Code" = RI,
        tabledata "Resolution Code" = RI,
        tabledata "Work Type" = RI,
        tabledata "Service Mgt. Setup" = RIM,
        tabledata "No. Series" = RI,
        tabledata "No. Series Line" = RI;

    procedure CreateMissingDefaults()
    var
        UOM: Record "Unit of Measure";
        MgtSetup: Record "Service Mgt. Setup";
        Setup: Record "DOPSWHS Service Setup";
        Priority: Record "Service Status Priority Setup";
        SetupChanged: Boolean;
    begin
        if not UOM.Get('SAAT') then begin
            UOM.Init();
            UOM.Code := 'SAAT';
            UOM.Description := 'Saat';
            UOM.Insert(true);
        end;
        AddPriority("Service Document Status"::"In Process", Priority.Priority::High);
        AddPriority("Service Document Status"::"On Hold", Priority.Priority::"Medium High");
        AddPriority("Service Document Status"::Pending, Priority.Priority::"Medium Low");
        AddPriority("Service Document Status"::Finished, Priority.Priority::Low);
        AddRepair('ILK', 'İlk', 0, "Service Document Status"::Pending);
        AddRepair('ISLEMDE', 'İşlemde', 1, "Service Document Status"::"In Process");
        AddRepair('BEKLEMUS', 'Müşteri bekleniyor', 2, "Service Document Status"::"On Hold");
        AddRepair('PARCA', 'Parça sipariş edildi', 3, "Service Document Status"::"On Hold");
        AddRepair('KISMI', 'Kısmen servis verildi', 4, "Service Document Status"::"In Process");
        AddRepair('BITTI', 'Tamamlandı', 5, "Service Document Status"::Finished);
        AddArea('BANT', 'Bant');
        AddArea('MOTOR', 'Motor');
        AddArea('RULO', 'Rulo');
        AddArea('ELEKTRIK', 'Elektrik');
        AddArea('GENEL', 'Genel');
        AddSymptom('DURDU', 'Durdu');
        AddSymptom('KAYMA', 'Kayma');
        AddSymptom('SES', 'Ses');
        AddSymptom('YIRTIK', 'Yırtık');
        AddSymptom('ISINMA', 'Isınma');
        AddResolution('DEGISIM', 'Değişim');
        AddResolution('AYAR', 'Ayar');
        AddResolution('TAMIR', 'Tamir');
        AddResolution('BAKIM', 'Bakım');
        AddResolution('TEMIZLIK', 'Temizlik');
        AddWork('MONTAJ', 'Montaj');
        AddWork('TAMIR', 'Tamir');
        AddWork('BAKIM', 'Bakım');
        if not MgtSetup.Get() then begin
            MgtSetup.Init();
            MgtSetup.Insert(true);
        end;
        if MgtSetup."Service Order Nos." = '' then begin
            AddSeries('SRV-SIP', 'SS000001');
            MgtSetup."Service Order Nos." := 'SRV-SIP';
            SetupChanged := true;
        end;
        if MgtSetup."Service Item Nos." = '' then begin
            AddSeries('SRV-MAD', 'SM000001');
            MgtSetup."Service Item Nos." := 'SRV-MAD';
            SetupChanged := true;
        end;
        if MgtSetup."Posted Service Shipment Nos." = '' then begin
            AddSeries('SRV-SEV', 'SV000001');
            MgtSetup."Posted Service Shipment Nos." := 'SRV-SEV';
            SetupChanged := true;
        end;
        if MgtSetup."Posted Service Invoice Nos." = '' then begin
            AddSeries('SRV-FAT', 'SF000001');
            MgtSetup."Posted Service Invoice Nos." := 'SRV-FAT';
            SetupChanged := true;
        end;
        if MgtSetup."Service Quote Nos." = '' then begin
            AddSeries('SRV-TKL', 'ST000001');
            MgtSetup."Service Quote Nos." := 'SRV-TKL';
            SetupChanged := true;
        end;
        if SetupChanged then
            MgtSetup.Modify(true);
        Setup.GetSetup();
        if Setup."Default Work Type Code" = '' then begin
            Setup.Validate("Default Work Type Code", 'TAMIR');
            Setup.Modify(true);
        end;
    end;

    local procedure AddPriority(Status: Enum "Service Document Status"; Priority: Option High,"Medium High","Medium Low",Low)
    var
        Rec: Record "Service Status Priority Setup";
    begin
        if Rec.Get(Status) then
            exit;
        Rec.Init();
        Rec."Service Order Status" := Status;
        Rec.Priority := Priority;
        Rec.Insert(true);
    end;

    local procedure AddRepair(Code: Code[10]; Description: Text[100]; Kind: Integer; Status: Enum "Service Document Status")
    var
        Rec: Record "Repair Status";
        Priority: Record "Service Status Priority Setup";
    begin
        if Rec.Get(Code) then
            exit;
        Rec.Init();
        Rec.Code := Code;
        Rec.Description := Description;
        Rec."Service Order Status" := Status;
        if Priority.Get(Status) then
            Rec.Priority := Priority.Priority;
        Rec.Initial := Kind = 0;
        Rec."In Process" := Kind = 1;
        Rec."Waiting for Customer" := Kind = 2;
        Rec."Spare Part Ordered" := Kind = 3;
        Rec."Partly Serviced" := Kind = 4;
        Rec.Finished := Kind = 5;
        Rec."Posting Allowed" := Kind = 5;
        Rec."Pending Status Allowed" := true;
        Rec."In Process Status Allowed" := true;
        Rec."Finished Status Allowed" := true;
        Rec."On Hold Status Allowed" := true;
        Rec.Insert(true);
    end;

    local procedure AddArea(Code: Code[10]; Description: Text[100])
    var
        Rec: Record "Fault Area";
        Fault: Record "Fault Code";
    begin
        if not Rec.Get(Code) then begin
            Rec.Init();
            Rec.Code := Code;
            Rec.Description := CopyStr(Description, 1, MaxStrLen(Rec.Description));
            Rec.Insert(true);
        end;
        if not Fault.Get(Code, '', 'GENEL') then begin
            Fault.Init();
            Fault."Fault Area Code" := Code;
            Fault.Code := 'GENEL';
            Fault.Description := 'Genel';
            Fault.Insert(true);
        end;
    end;

    local procedure AddSymptom(Code: Code[10]; Description: Text[100])
    var
        Rec: Record "Symptom Code";
    begin
        if Rec.Get(Code) then
            exit;
        Rec.Init();
        Rec.Code := Code;
        Rec.Description := CopyStr(Description, 1, MaxStrLen(Rec.Description));
        Rec.Insert(true);
    end;

    local procedure AddResolution(Code: Code[10]; Description: Text[100])
    var
        Rec: Record "Resolution Code";
    begin
        if Rec.Get(Code) then
            exit;
        Rec.Init();
        Rec.Code := Code;
        Rec.Description := CopyStr(Description, 1, MaxStrLen(Rec.Description));
        Rec.Insert(true);
    end;

    local procedure AddWork(Code: Code[10]; Description: Text[100])
    var
        Rec: Record "Work Type";
    begin
        if Rec.Get(Code) then
            exit;
        Rec.Init();
        Rec.Code := Code;
        Rec.Description := CopyStr(Description, 1, MaxStrLen(Rec.Description));
        Rec.Validate("Unit of Measure Code", 'SAAT');
        Rec.Insert(true);
    end;

    local procedure AddSeries(Code: Code[20]; StartingNo: Code[20])
    var
        Series: Record "No. Series";
        Line: Record "No. Series Line";
    begin
        if not Series.Get(Code) then begin
            Series.Init();
            Series.Code := Code;
            Series.Description := Code;
            Series."Default Nos." := true;
            Series."Manual Nos." := true;
            Series.Insert(true);
        end;
        Line.SetRange("Series Code", Code);
        if not Line.IsEmpty() then
            exit;
        Line.Init();
        Line."Series Code" := Code;
        Line."Line No." := 10000;
        Line.Validate("Starting No.", StartingNo);
        Line."Increment-by No." := 1;
        Line.Open := true;
        Line.Insert(true);
    end;
}
