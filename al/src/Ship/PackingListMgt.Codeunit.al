/// <summary>
/// Packing list for shipments and license plates (EMU/DKÇ, 15 Eyl 2026):
/// resolves the root containers of a warehouse shipment (open or posted) or a
/// single LP, flattens the pallet → carton → box → item hierarchy with SSCCs,
/// net/gross weights and container counters, and routes the RDLC report to
/// the document printer or the BC preview.
/// </summary>
codeunit 72319 "DOPSWHS Packing List Mgt."
{
    Access = Public;
    Permissions =
        tabledata "DOPSWHS LP Header" = R,
        tabledata "DOPSWHS LP Line" = R,
        tabledata "DOPSWHS LP Template" = R,
        tabledata "Warehouse Shipment Header" = R,
        tabledata "Warehouse Shipment Line" = R,
        tabledata "Posted Whse. Shipment Header" = RM,
        tabledata "Posted Whse. Shipment Line" = R,
        tabledata Item = R;

    // ------------------------------------------------------------------
    // Entry points
    // ------------------------------------------------------------------

    /// <summary>Queues the packing list PDF of a warehouse shipment on the document printer; returns the job id.</summary>
    procedure PrintForShipment(Posted: Boolean; ShipmentNo: Code[20]; PrinterId: Code[50]): Integer
    var
        RootLP: Record "DOPSWHS LP Header";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        SourceRecord: RecordRef;
    begin
        FilterRootLps(RootLP, Posted, ShipmentNo);
        SourceRecord.GetTable(RootLP);
        exit(PrintDispatcher.PrintReport(ShipmentNo, Report::"DOPSWHS Packing List", PrinterId, 1, Enum::"DOPSWHS IWX Report Usage"::PostedShipment, SourceRecord));
    end;

    procedure PrintForLp(LpNo: Code[20]; PrinterId: Code[50]): Integer
    var
        RootLP: Record "DOPSWHS LP Header";
        PrintDispatcher: Codeunit "DOPSWHS Print Dispatcher";
        SourceRecord: RecordRef;
    begin
        FilterRootLp(RootLP, LpNo);
        SourceRecord.GetTable(RootLP);
        exit(PrintDispatcher.PrintReport(LpNo, Report::"DOPSWHS Packing List", PrinterId, 1, Enum::"DOPSWHS IWX Report Usage"::PostedShipment, SourceRecord));
    end;

    /// <summary>BC client: preview/print dialog for a shipment's packing list.</summary>
    procedure RunForShipment(Posted: Boolean; ShipmentNo: Code[20])
    var
        RootLP: Record "DOPSWHS LP Header";
    begin
        FilterRootLps(RootLP, Posted, ShipmentNo);
        Report.RunModal(Report::"DOPSWHS Packing List", true, false, RootLP);
    end;

    procedure RunForLp(LpNo: Code[20])
    var
        RootLP: Record "DOPSWHS LP Header";
    begin
        FilterRootLp(RootLP, LpNo);
        Report.RunModal(Report::"DOPSWHS Packing List", true, false, RootLP);
    end;

    // ------------------------------------------------------------------
    // Root containers
    // ------------------------------------------------------------------

    local procedure FilterRootLp(var RootLP: Record "DOPSWHS LP Header"; LpNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        NestManager: Codeunit "DOPSWHS LP Nest Manager";
    begin
        LP.Get(LpNo);
        RootLP.Reset();
        RootLP.SetRange("No.", NestManager.GetRootLP(LP));
    end;

    /// <summary>
    /// Root LPs of a shipment: the header LP, every line LP, the LPs assigned
    /// to the shipment and (posted) the LPs whose source is the posted document,
    /// each walked up to its top-most parent so nested containers print once.
    /// </summary>
    local procedure FilterRootLps(var RootLP: Record "DOPSWHS LP Header"; Posted: Boolean; ShipmentNo: Code[20])
    var
        LP: Record "DOPSWHS LP Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        PostedHeader: Record "Posted Whse. Shipment Header";
        PostedLine: Record "Posted Whse. Shipment Line";
        NestManager: Codeunit "DOPSWHS LP Nest Manager";
        Roots: List of [Code[20]];
        Candidates: List of [Code[20]];
        LpNo: Code[20];
        FilterText: Text;
    begin
        if ShipmentNo = '' then
            Error(ShipmentNoRequiredErr);
        if Posted then begin
            if PostedHeader.Get(ShipmentNo) then
                AddCandidate(Candidates, PostedHeader."DOPSWHS LP No.");
            PostedLine.SetRange("No.", ShipmentNo);
            if PostedLine.FindSet() then
                repeat
                    AddCandidate(Candidates, PostedLine."LP No.");
                until PostedLine.Next() = 0;
            LP.SetRange("Source Document Type", LP."Source Document Type"::PostedWhseShipment);
            LP.SetRange("Source Document No.", ShipmentNo);
            if LP.FindSet() then
                repeat
                    AddCandidate(Candidates, LP."No.");
                until LP.Next() = 0;
            LP.Reset();
            if PostedHeader."Whse. Shipment No." <> '' then begin
                LP.SetRange("Source Document Type", LP."Source Document Type"::WhseShipment);
                LP.SetRange("Source Document No.", PostedHeader."Whse. Shipment No.");
                if LP.FindSet() then
                    repeat
                        AddCandidate(Candidates, LP."No.");
                    until LP.Next() = 0;
                LP.Reset();
            end;
        end else begin
            if WhseShipmentHeader.Get(ShipmentNo) then
                AddCandidate(Candidates, WhseShipmentHeader."DOPSWHS LP No.");
            WhseShipmentLine.SetRange("No.", ShipmentNo);
            if WhseShipmentLine.FindSet() then
                repeat
                    AddCandidate(Candidates, WhseShipmentLine."LP No.");
                until WhseShipmentLine.Next() = 0;
            LP.SetRange("Assigned Document Type", LP."Assigned Document Type"::WhseShipment);
            LP.SetRange("Assigned Document No.", ShipmentNo);
            if LP.FindSet() then
                repeat
                    AddCandidate(Candidates, LP."No.");
                until LP.Next() = 0;
            LP.Reset();
            LP.SetRange("Source Document Type", LP."Source Document Type"::WhseShipment);
            LP.SetRange("Source Document No.", ShipmentNo);
            if LP.FindSet() then
                repeat
                    AddCandidate(Candidates, LP."No.");
                until LP.Next() = 0;
            LP.Reset();
        end;

        foreach LpNo in Candidates do
            if LP.Get(LpNo) then
                AddCandidate(Roots, NestManager.GetRootLP(LP));
        if Roots.Count() = 0 then
            Error(NoLpsErr, ShipmentNo);

        foreach LpNo in Roots do begin
            if FilterText <> '' then
                FilterText += '|';
            FilterText += LpNo;
        end;
        RootLP.Reset();
        RootLP.SetFilter("No.", FilterText);
    end;

    local procedure AddCandidate(var Candidates: List of [Code[20]]; LpNo: Code[20])
    begin
        if LpNo = '' then
            exit;
        if not Candidates.Contains(LpNo) then
            Candidates.Add(LpNo);
    end;

    // ------------------------------------------------------------------
    // Hierarchy
    // ------------------------------------------------------------------

    /// <summary>
    /// Flattens one root container into the buffer (appending after the last
    /// entry) and returns its net/gross weight and the number of nested
    /// containers. Counters per container kind are accumulated in Counters
    /// keyed by the kind caption ('' = unspecified).
    /// </summary>
    procedure BuildForRootLp(RootLP: Record "DOPSWHS LP Header"; var Buffer: Record "DOPSWHS Packing List Buffer"; var Counters: Dictionary of [Text, Integer]; var RootNet: Decimal; var RootGross: Decimal; var ContainerCount: Integer)
    var
        Builder: Codeunit "DOPSWHS LP Label Builder";
        StartEntry: Integer;
        EntryNo: Integer;
    begin
        Clear(RootNet);
        Clear(RootGross);
        Clear(ContainerCount);
        if Buffer.FindLast() then
            EntryNo := Buffer."Entry No.";
        StartEntry := EntryNo + 1;
        CountKind(Counters, Builder.ContainerKindCaption(RootLP."No."));
        AppendContainer(RootLP, RootLP, 1, 0, Buffer, Counters, EntryNo, RootNet, RootGross, ContainerCount);
        // Root totals become known only after the walk: stamp them on every row.
        Buffer.SetRange("Entry No.", StartEntry, EntryNo);
        if Buffer.FindSet() then
            repeat
                Buffer."Root Net Weight kg" := RootNet;
                Buffer."Root Gross Weight kg" := RootGross;
                Buffer."Root Container Count" := ContainerCount;
                Buffer.Modify();
            until Buffer.Next() = 0;
        Buffer.Reset();
    end;

    local procedure AppendContainer(RootLP: Record "DOPSWHS LP Header"; Container: Record "DOPSWHS LP Header"; Level: Integer; Depth: Integer; var Buffer: Record "DOPSWHS Packing List Buffer"; var Counters: Dictionary of [Text, Integer]; var EntryNo: Integer; var NetTotal: Decimal; var GrossTotal: Decimal; var ContainerCount: Integer)
    var
        LPLine: Record "DOPSWHS LP Line";
        Child: Record "DOPSWHS LP Header";
        Item: Record Item;
        Builder: Codeunit "DOPSWHS LP Label Builder";
        ContainerNet: Decimal;
        ContainerGross: Decimal;
        ChildNet: Decimal;
        ChildGross: Decimal;
        ChildCount: Integer;
        HeaderEntry: Integer;
    begin
        // Container row (level 1 for the root, 2 for nested containers).
        EntryNo += 1;
        HeaderEntry := EntryNo;
        InitRow(Buffer, EntryNo, RootLP, Level);
        if Level > 1 then
            SetChild(Buffer, Container, Depth);
        Buffer."Container LP No." := Container."No.";
        Buffer.Insert();

        // Item lines of this container.
        LPLine.SetRange("LP No.", Container."No.");
        LPLine.SetFilter("Item No.", '<>%1', '');
        if LPLine.FindSet() then
            repeat
                EntryNo += 1;
                InitRow(Buffer, EntryNo, RootLP, 3);
                if Level > 1 then
                    SetChild(Buffer, Container, Depth);
                Buffer."Container LP No." := Container."No.";
                Buffer."Item No." := LPLine."Item No.";
                if Item.Get(LPLine."Item No.") then
                    Buffer.Description := Item.Description;
                Buffer."Variant Code" := LPLine."Variant Code";
                Buffer."Lot No." := LPLine."Lot No.";
                Buffer."Serial No." := LPLine."Serial No.";
                Buffer.Quantity := LPLine.Quantity;
                Buffer."Unit of Measure" := LPLine."Unit of Measure";
                Buffer."Expiration Date" := LPLine."Expiration Date";
                Buffer."Line Weight kg" := LPLine."Line Weight kg";
                Buffer.Insert();
                ContainerNet += LPLine."Line Weight kg";
            until LPLine.Next() = 0;
        ContainerGross := ContainerNet + TareWeight(Container);

        // Nested containers.
        Child.SetRange("Parent LP No.", Container."No.");
        if Child.FindSet() then
            repeat
                ChildCount += 1;
                CountKind(Counters, Builder.ContainerKindCaption(Child."No."));
                Clear(ChildNet);
                Clear(ChildGross);
                AppendContainer(RootLP, Child, 2, Depth + 1, Buffer, Counters, EntryNo, ChildNet, ChildGross, ContainerCount);
                ContainerNet += ChildNet;
                ContainerGross += ChildGross;
            until Child.Next() = 0;
        ContainerCount += ChildCount;

        // Stamp the container's own totals on its header row and its item rows.
        Buffer.SetRange("Entry No.", HeaderEntry, EntryNo);
        Buffer.SetRange("Container LP No.", Container."No.");
        if Buffer.FindSet() then
            repeat
                if Level > 1 then begin
                    Buffer."Child Net Weight kg" := ContainerNet;
                    Buffer."Child Gross Weight kg" := ContainerGross;
                    Buffer.Modify();
                end;
            until Buffer.Next() = 0;
        Buffer.Reset();

        NetTotal += ContainerNet;
        GrossTotal += ContainerGross;
    end;

    local procedure InitRow(var Buffer: Record "DOPSWHS Packing List Buffer"; EntryNo: Integer; RootLP: Record "DOPSWHS LP Header"; Level: Integer)
    var
        Builder: Codeunit "DOPSWHS LP Label Builder";
    begin
        Buffer.Init();
        Buffer."Entry No." := EntryNo;
        Buffer.Level := Level;
        Buffer."Root LP No." := RootLP."No.";
        Buffer."Root SSCC" := RootLP.SSCC;
        Buffer."Root Kind" := CopyStr(Builder.ContainerKindCaption(RootLP."No."), 1, MaxStrLen(Buffer."Root Kind"));
    end;

    local procedure SetChild(var Buffer: Record "DOPSWHS Packing List Buffer"; Child: Record "DOPSWHS LP Header"; Depth: Integer)
    var
        Builder: Codeunit "DOPSWHS LP Label Builder";
    begin
        Buffer."Child LP No." := Child."No.";
        Buffer."Child SSCC" := Child.SSCC;
        Buffer."Child Kind" := CopyStr(Builder.ContainerKindCaption(Child."No."), 1, MaxStrLen(Buffer."Child Kind"));
        Buffer."Child Depth" := Depth;
    end;

    local procedure TareWeight(LP: Record "DOPSWHS LP Header"): Decimal
    var
        Template: Record "DOPSWHS LP Template";
    begin
        if LP."Tare Weight kg" <> 0 then
            exit(LP."Tare Weight kg");
        if (LP."LP Template Code" <> '') and Template.Get(LP."LP Template Code") then
            exit(Template."Default Tare Weight kg");
        exit(0);
    end;

    local procedure CountKind(var Counters: Dictionary of [Text, Integer]; Kind: Text)
    begin
        if Counters.ContainsKey(Kind) then
            Counters.Set(Kind, Counters.Get(Kind) + 1)
        else
            Counters.Add(Kind, 1);
    end;

    procedure KindCount(var Counters: Dictionary of [Text, Integer]; Kind: Enum "DOPSWHS LP Container Kind"): Integer
    var
        Caption: Text;
    begin
        Caption := Format(Kind);
        if Counters.ContainsKey(Caption) then
            exit(Counters.Get(Caption));
        exit(0);
    end;

    // ------------------------------------------------------------------
    // Shipment header data for the printed list
    // ------------------------------------------------------------------

    /// <summary>
    /// Container / seal come from the warehouse shipment when the LP still
    /// points at it; everything else is the LP's own document snapshot.
    /// </summary>
    procedure ResolveContainerInfo(RootLP: Record "DOPSWHS LP Header"; var ContainerNo: Code[30]; var SealNo: Code[30])
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        PostedHeader: Record "Posted Whse. Shipment Header";
    begin
        ContainerNo := RootLP."Container No.";
        SealNo := RootLP."Seal No.";
        case RootLP."Source Document Type" of
            RootLP."Source Document Type"::WhseShipment:
                if WhseShipmentHeader.Get(RootLP."Source Document No.") then begin
                    if WhseShipmentHeader."DOPSWHS Container No." <> '' then
                        ContainerNo := WhseShipmentHeader."DOPSWHS Container No.";
                    if WhseShipmentHeader."DOPSWHS Seal No." <> '' then
                        SealNo := WhseShipmentHeader."DOPSWHS Seal No.";
                end;
            RootLP."Source Document Type"::PostedWhseShipment:
                if PostedHeader.Get(RootLP."Source Document No.") then begin
                    if PostedHeader."DOPSWHS Container No." <> '' then
                        ContainerNo := PostedHeader."DOPSWHS Container No.";
                    if PostedHeader."DOPSWHS Seal No." <> '' then
                        SealNo := PostedHeader."DOPSWHS Seal No.";
                end;
        end;
    end;

    /// <summary>Container and seal numbers follow the shipment into its posted document.</summary>
    [EventSubscriber(ObjectType::Table, Database::"Posted Whse. Shipment Header", 'OnBeforeInsertEvent', '', false, false)]
    local procedure CarryContainerOntoPostedShipment(var Rec: Record "Posted Whse. Shipment Header"; RunTrigger: Boolean)
    var
        WhseShipmentHeader: Record "Warehouse Shipment Header";
    begin
        if Rec.IsTemporary() then
            exit;
        if Rec."Whse. Shipment No." = '' then
            exit;
        if not WhseShipmentHeader.Get(Rec."Whse. Shipment No.") then
            exit;
        if Rec."DOPSWHS Container No." = '' then
            Rec."DOPSWHS Container No." := WhseShipmentHeader."DOPSWHS Container No.";
        if Rec."DOPSWHS Seal No." = '' then
            Rec."DOPSWHS Seal No." := WhseShipmentHeader."DOPSWHS Seal No.";
    end;

    var
        ShipmentNoRequiredErr: Label 'Sevkiyat numarası girin.';
        NoLpsErr: Label '%1 sevkiyatında paketleme listesi için LP bulunamadı. Satırlara veya sevkiyata LP atayın.', Comment = '%1 shipment no';
}
