table 72190 "DOPS Svc Seed"
{
    DataClassification = SystemMetadata;
    fields
    {
        field(1; "Code"; Code[10]) { }
        field(2; "Last Result"; Text[2048]) { }
    }
    keys { key(PK; "Code") { Clustered = true; } }
}

page 72190 "DOPS Svc Seed API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'seed';
    APIVersion = 'v1.0';
    EntityName = 'serviceSeed';
    EntitySetName = 'serviceSeeds';
    SourceTable = "DOPS Svc Seed";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { }
                field(code; Rec."Code") { }
                field(lastResult; Rec."Last Result") { }
            }
        }
    }

    trigger OnOpenPage()
    begin
        if not Rec.Get('SEED') then begin
            Rec.Init();
            Rec."Code" := 'SEED';
            Rec.Insert();
        end;
    end;

    [ServiceEnabled]
    procedure resetSeed(): Text
    var
        Seeder: Codeunit "DOPS Svc Seeder";
        Result: Text;
    begin
        Seeder.DeleteDemoOrders();
        Result := Seeder.Seed();
        Rec."Last Result" := CopyStr(Result, 1, MaxStrLen(Rec."Last Result"));
        Rec.Modify();
        exit(Result);
    end;

    [ServiceEnabled]
    procedure runSeed(): Text
    var
        Seeder: Codeunit "DOPS Svc Seeder";
        Result: Text;
    begin
        Result := Seeder.Seed();
        Rec."Last Result" := CopyStr(Result, 1, MaxStrLen(Rec."Last Result"));
        Rec.Modify();
        exit(Result);
    end;
}

codeunit 72191 "DOPS Svc Seeder"
{
    Permissions = tabledata Resource = RIM, tabledata "Resource Unit of Measure" = RIM, tabledata "Service Item" = RIM,
        tabledata "Service Item Group" = RIM, tabledata "Service Header" = RIMD, tabledata "Service Item Line" = RIM,
        tabledata "Symptom Code" = RIM, tabledata "Resolution Code" = RIM, tabledata "Fault Code" = RIM, tabledata "Fault Area" = RIM,
        tabledata "DOPSWHS Service Setup" = RIM, tabledata "Service Mgt. Setup" = RIM, tabledata "No. Series" = RI, tabledata "No. Series Line" = RI, tabledata "DOPSWHS Service Technician" = RIM;

    var
        Log: TextBuilder;

    procedure Seed(): Text
    var
        EnvInfo: Codeunit "Environment Information";
        Defaults: Codeunit "DOPSWHS Service Defaults";
        GenProd: Code[20];
        VatProd: Code[20];
        SiAkcansa: Code[20];
        SiAksa: Code[20];
        SiTupras: Code[20];
        OrderNo: Code[20];
    begin
        if not EnvInfo.IsSandbox() then
            Error('Bu demo verisi yalnız sandbox ortamında oluşturulabilir.');
        SetFaultLevel();
        Defaults.CreateMissingDefaults();
        Log.AppendLine('defaults ok');

        AddSymptom('ASINMA', 'Bant yüzeyinde aşınma');
        AddSymptom('EKACILMA', 'Bant ekinde açılma');
        AddResolution('VULKANIZE', 'Sıcak vulkanize ek yapıldı');
        AddResolution('SOGUKEK', 'Soğuk ek yapıldı');
        AddFault('BANT', 'YIRTIK', 'YIRTIK', 'Bant yırtığı');
        AddFault('BANT', 'EKACILMA', 'EK', 'Ek bölgesi arızası');
        AddFault('BANT', 'KAYMA', 'GERGI', 'Gergi / hizalama sorunu');
        AddFault('RULO', 'SES', 'RULMAN', 'Taşıyıcı rulo rulmanı');

        PickPostingGroups(GenProd, VatProd);
        AddResource('TEKN01', 'Ahmet Saha', GenProd, VatProd);
        AddResource('TEKN02', 'Mehmet Usta', GenProd, VatProd);

        AddServiceItemGroup('KONVEYOR', 'Konveyör hatları');
        SiAkcansa := AddServiceItem('120.01.00008', 'K-12 klinker taşıma bandı (1200 mm)', 'AKC-K12');
        SiAksa := AddServiceItem('120.01.00002', 'B-3 hammadde besleme konveyörü', 'AKS-B3');
        SiTupras := AddServiceItem('120.01.00004', 'H-7 kok taşıma hattı', 'TUP-H7');

        SetupTerminal();

        OrderNo := AddOrder('120.01.00008', SiAkcansa, 'K-12 bandında yırtık, ek yapılacak', 'Bant ortasında 40 cm yırtık; hat durdu.');
        SetPriority(OrderNo, 2);
        OrderNo := AddOrder('120.01.00002', SiAksa, 'B-3 konveyör periyodik bakım', 'Aylık bakım: rulo ve gergi kontrolü.');
        Allocate(OrderNo, 'TEKN01', 2);
        OrderNo := AddOrder('120.01.00004', SiTupras, 'H-7 hattında bant kayması', 'Tahrik tamburunda kayma, ses var.');
        SetPriority(OrderNo, 1);
        Allocate(OrderNo, 'TEKN01', 3);
        exit(Log.ToText());
    end;

    procedure DeleteDemoOrders()
    var
        SH: Record "Service Header";
        EnvInfo: Codeunit "Environment Information";
    begin
        if not EnvInfo.IsSandbox() then
            Error('Yalnız sandbox.');
        SH.SetRange("Document Type", SH."Document Type"::Order);
        SH.SetFilter(Description, '%1|%2|%3', 'K-12 bandında yırtık, ek yapılacak', 'B-3 konveyör periyodik bakım', 'H-7 hattında bant kayması');
        if SH.FindSet(true) then
            repeat
                SH.Delete(true);
            until SH.Next() = 0;
        Log.AppendLine('demo orders deleted');
    end;

    local procedure SetFaultLevel()
    var
        MgtSetup: Record "Service Mgt. Setup";
    begin
        if not MgtSetup.Get() then begin
            MgtSetup.Init();
            MgtSetup.Insert();
        end;
        MgtSetup."Fault Reporting Level" := MgtSetup."Fault Reporting Level"::"Fault+Symptom+Area (IRIS)";
        // Sandbox: the copied production setup points service orders at an already used series.
        MgtSetup."Service Order Nos." := Series('SRV-SIP', 'Servis siparişleri', 'SS000001');
        MgtSetup."Service Item Nos." := Series('SRV-MAD', 'Servis maddeleri', 'SM000001');
        MgtSetup."Posted Service Shipment Nos." := Series('SRV-SEV', 'Kayıtlı servis sevkiyatları', 'SV000001');
        MgtSetup."Posted Service Invoice Nos." := Series('SRV-FAT', 'Kayıtlı servis faturaları', 'SF000001');
        MgtSetup.Modify();
        Log.AppendLine('service numbering SRV-*');
    end;

    local procedure Series(Code: Code[20]; Descr: Text[100]; StartNo: Code[20]): Code[20]
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        if not NoSeries.Get(Code) then begin
            NoSeries.Init(); NoSeries.Code := Code; NoSeries.Description := Descr; NoSeries."Default Nos." := true; NoSeries."Manual Nos." := true; NoSeries.Insert();
            NoSeriesLine.Init(); NoSeriesLine."Series Code" := Code; NoSeriesLine."Line No." := 10000; NoSeriesLine."Starting No." := StartNo; NoSeriesLine."Increment-by No." := 1; NoSeriesLine.Insert();
        end;
        exit(Code);
    end;

    local procedure AddSymptom(Code: Code[10]; Descr: Text[100])
    var
        S: Record "Symptom Code";
    begin
        if S.Get(Code) then exit;
        S.Init(); S.Code := Code; S.Description := Descr; S.Insert();
    end;

    local procedure AddResolution(Code: Code[10]; Descr: Text[80])
    var
        R: Record "Resolution Code";
    begin
        if R.Get(Code) then exit;
        R.Init(); R.Code := Code; R.Description := Descr; R.Insert();
    end;

    local procedure AddFault(AreaCode: Code[10]; Symptom: Code[10]; Code: Code[10]; Descr: Text[80])
    var
        F: Record "Fault Code";
        FA: Record "Fault Area";
        S: Record "Symptom Code";
    begin
        if not FA.Get(AreaCode) then begin
            FA.Init(); FA.Code := AreaCode; FA.Description := AreaCode; FA.Insert();
        end;
        if not S.Get(Symptom) then
            AddSymptom(Symptom, Symptom);
        if F.Get(AreaCode, Symptom, Code) then exit;
        F.Init(); F."Fault Area Code" := AreaCode; F."Symptom Code" := Symptom; F.Code := Code; F.Description := Descr; F.Insert();
    end;

    local procedure PickPostingGroups(var GenProd: Code[20]; var VatProd: Code[20])
    var
        Item: Record Item;
    begin
        Item.SetRange("Gen. Prod. Posting Group", 'M_MAMUL');
        Item.SetFilter("VAT Prod. Posting Group", '<>%1', '');
        if not Item.FindFirst() then begin
            Item.Reset();
            Item.SetFilter("Gen. Prod. Posting Group", '<>%1', '');
            Item.SetFilter("VAT Prod. Posting Group", '<>%1', '');
            Item.FindFirst();
        end;
        GenProd := Item."Gen. Prod. Posting Group";
        VatProd := Item."VAT Prod. Posting Group";
        Log.AppendLine(StrSubstNo('posting groups %1 / %2', GenProd, VatProd));
    end;

    local procedure AddResource(No: Code[20]; Name: Text[100]; GenProd: Code[20]; VatProd: Code[20])
    var
        Res: Record Resource;
        ResUom: Record "Resource Unit of Measure";
    begin
        if not Res.Get(No) then begin
            Res.Init();
            Res."No." := No;
            Res.Insert(true);
        end;
        if not ResUom.Get(No, 'SAAT') then begin
            ResUom.Init(); ResUom."Resource No." := No; ResUom.Code := 'SAAT'; ResUom."Qty. per Unit of Measure" := 1; ResUom."Related to Base Unit of Meas." := true; ResUom.Insert();
        end;
        Res.Get(No);
        Res.Type := Res.Type::Person;
        Res.Validate(Name, Name);
        Res.Validate("Base Unit of Measure", 'SAAT');
        Res.Validate("Gen. Prod. Posting Group", GenProd);
        Res.Validate("VAT Prod. Posting Group", VatProd);
        Res.Validate("Direct Unit Cost", 600);
        Res.Validate("Unit Price", 1500);
        Res.Modify(true);
        Log.AppendLine('resource ' + No);
    end;

    local procedure AddServiceItemGroup(Code: Code[10]; Descr: Text[100])
    var
        G: Record "Service Item Group";
    begin
        if G.Get(Code) then exit;
        G.Init(); G.Code := Code; G.Description := Descr; G.Insert();
    end;

    local procedure AddServiceItem(CustomerNo: Code[20]; Descr: Text[100]; Serial: Code[50]): Code[20]
    var
        SI: Record "Service Item";
    begin
        SI.SetRange("Serial No.", Serial);
        if SI.FindFirst() then exit(SI."No.");
        SI.Init();
        SI.Insert(true);
        SI.Validate(Description, Descr);
        SI.Validate("Customer No.", CustomerNo);
        SI.Validate("Service Item Group Code", 'KONVEYOR');
        SI."Serial No." := Serial;
        SI.Modify(true);
        Log.AppendLine('service item ' + SI."No.");
        exit(SI."No.");
    end;

    local procedure SetupTerminal()
    var
        Setup: Record "DOPSWHS Service Setup";
        Tech: Record "DOPSWHS Service Technician";
    begin
        Setup.GetSetup();
        Setup.Enabled := true;
        Setup."Hide Warehouse Modules" := true;
        Setup."Default Location Code" := 'MERKEZ';
        Setup."Allow Terminal Posting" := true;
        Setup.Modify();
        if not Tech.Get(UserId()) then begin
            Tech.Init();
            Tech."User Name" := CopyStr(UserId(), 1, MaxStrLen(Tech."User Name"));
            Tech.Insert();
        end;
        Tech.Validate("Resource No.", 'TEKN01');
        Tech."Van Location Code" := 'MERKEZ';
        Tech.Dispatcher := true;
        Tech.Active := true;
        Tech.Modify();
        Log.AppendLine('technician ' + Tech."User Name" + ' -> TEKN01');
    end;

    local procedure AddOrder(CustomerNo: Code[20]; ServiceItemNo: Code[20]; Descr: Text[100]; Fault: Text): Code[20]
    var
        SH: Record "Service Header";
        SIL: Record "Service Item Line";
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        SH.SetRange("Document Type", SH."Document Type"::Order);
        SH.SetRange(Description, Descr);
        if SH.FindFirst() then exit(SH."No.");
        SH.Init();
        SH."Document Type" := SH."Document Type"::Order;
        SH.Insert(true);
        SH.Validate("Customer No.", CustomerNo);
        SH.Validate(Description, Descr);
        SH.Validate("Location Code", 'MERKEZ');
        SH.Modify(true);
        SIL.Init();
        SIL."Document Type" := SH."Document Type";
        SIL."Document No." := SH."No.";
        SIL."Line No." := 10000;
        SIL.Insert(true);
        SIL.Validate("Service Item No.", ServiceItemNo);
        SIL.Modify(true);
        Mgt.AddComment(SH."No.", 10000, 'Fault', Fault);
        Log.AppendLine('order ' + SH."No.");
        exit(SH."No.");
    end;

    local procedure SetPriority(OrderNo: Code[20]; Level: Integer)
    var
        SH: Record "Service Header";
        SIL: Record "Service Item Line";
    begin
        SH.Get(SH."Document Type"::Order, OrderNo);
        case Level of
            1: SH.Validate(Priority, SH.Priority::Medium);
            2: SH.Validate(Priority, SH.Priority::High);
        end;
        SH.Modify(true);
        SIL.SetRange("Document Type", SH."Document Type");
        SIL.SetRange("Document No.", OrderNo);
        if SIL.FindSet(true) then
            repeat
                case Level of
                    1: SIL.Validate(Priority, SIL.Priority::Medium);
                    2: SIL.Validate(Priority, SIL.Priority::High);
                end;
                SIL.Modify(true);
            until SIL.Next() = 0;
    end;

    local procedure Allocate(OrderNo: Code[20]; ResourceNo: Code[20]; Hours: Decimal)
    var
        Alloc: Record "Service Order Allocation";
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        Alloc.SetRange("Document No.", OrderNo);
        Alloc.SetRange("Resource No.", ResourceNo);
        Alloc.SetRange(Status, Alloc.Status::Active);
        if not Alloc.IsEmpty() then exit;
        Mgt.AssignTechnician(OrderNo, 10000, ResourceNo, Today(), Hours);
        Log.AppendLine('allocated ' + OrderNo + ' -> ' + ResourceNo);
    end;
}
