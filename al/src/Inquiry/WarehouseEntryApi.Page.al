page 72215 "DOPSWHS Warehouse Entry API"
{
    // Bin Inquiry "Whse Entries" (raf hareket geçmişi) — müşteri isteği.
    // Salt-okunur; mobil app locationCode+binCode ile filtreleyip tarihe göre sıralar.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'warehouseEntry';
    EntitySetName = 'warehouseEntries';
    SourceTable = "Warehouse Entry";
    ODataKeyFields = "Entry No.";
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(entryNo; Rec."Entry No.") { Caption = 'entryNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(zoneCode; Rec."Zone Code") { Caption = 'zoneCode'; }
                field(entryType; Rec."Entry Type") { Caption = 'entryType'; }
                field(registeringDate; Rec."Registering Date") { Caption = 'registeringDate'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(qtyBase; Rec."Qty. (Base)") { Caption = 'qtyBase'; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; }
                field(lpNo; ResolvedLpNo) { Caption = 'lpNo'; }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        ResolvedLpNo := Rec."DOPSWHS LP No.";
        if ResolvedLpNo = '' then
            ResolvedLpNo := InferLegacyMovementLp(Rec);
    end;

    /// <summary>
    /// 1.14.1.9 and earlier did not copy the LP field to the warehouse journal
    /// used by an LP bin move. Those already-posted entries cannot be changed
    /// during a read, but a recent single-LP move can be identified safely from
    /// the immutable LP movement ledger. Return a value only when all matching
    /// records point to one LP; ambiguous history remains blank.
    /// </summary>
    local procedure InferLegacyMovementLp(WarehouseEntry: Record "Warehouse Entry"): Code[20]
    var
        MovementLedger: Record "DOPSWHS LP Movement Ledger";
        LPHeader: Record "DOPSWHS LP Header";
        CandidateLpNo: Code[20];
        EntryDate: Date;
    begin
        if (WarehouseEntry."Entry Type" <> WarehouseEntry."Entry Type"::Movement) or
           (WarehouseEntry.Quantity = 0)
        then
            exit('');

        EntryDate := WarehouseEntry."Registering Date";
        if EntryDate = 0D then
            exit('');
        MovementLedger.SetRange(Action, MovementLedger.Action::TransferOut);
        MovementLedger.SetRange(Quantity, Abs(WarehouseEntry.Quantity));
        MovementLedger.SetRange("Related Document", 'BIN-MOVE');
        MovementLedger.SetRange(
            DateTime,
            CreateDateTime(EntryDate, 000000T),
            CreateDateTime(EntryDate, 235959T));
        if WarehouseEntry.Quantity < 0 then
            MovementLedger.SetRange("From Bin", WarehouseEntry."Bin Code")
        else
            MovementLedger.SetRange("To Bin", WarehouseEntry."Bin Code");

        if MovementLedger.FindSet() then
            repeat
                if LegacyMovementLpMatchesEntry(MovementLedger."LP No.", WarehouseEntry, LPHeader) then
                    if CandidateLpNo = '' then
                        CandidateLpNo := MovementLedger."LP No."
                    else
                        if CandidateLpNo <> MovementLedger."LP No." then
                            exit('');
            until MovementLedger.Next() = 0;
        exit(CandidateLpNo);
    end;

    local procedure LegacyMovementLpMatchesEntry(LpNo: Code[20]; WarehouseEntry: Record "Warehouse Entry"; var LPHeader: Record "DOPSWHS LP Header"): Boolean
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if (LpNo = '') or (not LPHeader.Get(LpNo)) then
            exit(false);
        if LPHeader."Location Code" <> WarehouseEntry."Location Code" then
            exit(false);
        LPLine.SetRange("LP No.", LpNo);
        LPLine.SetRange("Item No.", WarehouseEntry."Item No.");
        LPLine.SetRange("Variant Code", WarehouseEntry."Variant Code");
        LPLine.SetRange("Lot No.", WarehouseEntry."Lot No.");
        LPLine.SetRange("Serial No.", WarehouseEntry."Serial No.");
        exit(not LPLine.IsEmpty());
    end;

    var
        ResolvedLpNo: Code[20];
}
