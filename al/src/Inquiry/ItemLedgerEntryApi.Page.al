page 72214 "DOPSWHS Item Ledger Entry API"
{
    // Item Inquiry "Son Hareketler" (recent transactions) — müşteri isteği.
    // Salt-okunur; mobil app itemNo ile filtreleyip postingDate'e göre sıralar.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'itemLedgerEntry';
    EntitySetName = 'itemLedgerEntries';
    SourceTable = "Item Ledger Entry";
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
                field(postingDate; Rec."Posting Date") { Caption = 'postingDate'; }
                field(entryType; Rec."Entry Type") { Caption = 'entryType'; }
                field(documentNo; Rec."Document No.") { Caption = 'documentNo'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(remainingQuantity; Rec."Remaining Quantity") { Caption = 'remainingQuantity'; }
                field(allocatedLpQuantity; AllocatedLPQuantity) { Caption = 'allocatedLpQuantity'; }
                field(lpAllocatableQuantity; LPAllocatableQuantity) { Caption = 'lpAllocatableQuantity'; }
                field(baseUnitOfMeasure; BaseUnitOfMeasure) { Caption = 'baseUnitOfMeasure'; }
                field(variantCode; Rec."Variant Code") { Caption = 'variantCode'; }
                field(lotNo; Rec."Lot No.") { Caption = 'lotNo'; }
                field(serialNo; Rec."Serial No.") { Caption = 'serialNo'; }
                field(lpNo; Rec."DOPSWHS LP No.") { Caption = 'lpNo'; }
                field(lpNos; Rec."DOPSWHS LP Nos.") { Caption = 'lpNos'; }
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Item: Record Item;
    begin
        BaseUnitOfMeasure := '';
        if Item.Get(Rec."Item No.") then
            BaseUnitOfMeasure := Item."Base Unit of Measure";
        AllocatedLPQuantity := LPManagement.AllocatedQuantityForItemLedgerEntry(Rec."Entry No.");
        LPAllocatableQuantity := Rec."Remaining Quantity" - AllocatedLPQuantity;
        if LPAllocatableQuantity < 0 then
            LPAllocatableQuantity := 0;
    end;

    [ServiceEnabled]
    procedure createLicensePlates(templateCode: Code[20]; binCode: Code[20]; lpCount: Integer; quantityPerLp: Decimal; printerId: Code[50]; printLabels: Boolean): Text
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        CreatedLpNos: List of [Code[20]];
    begin
        LPMgt.BuildManyFromItemLedgerEntry(Rec."Entry No.", templateCode, binCode, lpCount, quantityPerLp, CreatedLpNos);
        exit(FinishBulkLpCreation(CreatedLpNos, printLabels, printerId, false));
    end;

    [ServiceEnabled]
    procedure createLicensePlatesIdempotent(templateCode: Code[20]; binCode: Code[20]; lpCount: Integer; quantityPerLp: Decimal; printerId: Code[50]; printLabels: Boolean; requestId: Guid): Text
    var
        LPMgt: Codeunit "DOPSWHS LP Management";
        CreatedLpNos: List of [Code[20]];
        Replayed: Boolean;
    begin
        LPMgt.BuildManyFromItemLedgerEntryIdempotent(
            Rec."Entry No.", templateCode, binCode, lpCount, quantityPerLp,
            requestId, CreatedLpNos, Replayed);
        exit(FinishBulkLpCreation(CreatedLpNos, printLabels, printerId, Replayed));
    end;

    local procedure FinishBulkLpCreation(var CreatedLpNos: List of [Code[20]]; PrintLabels: Boolean; PrinterId: Code[50]; Replayed: Boolean): Text
    var
        LP: Record "DOPSWHS LP Header";
        LPMgt: Codeunit "DOPSWHS LP Management";
        FailedPrintLpNos: List of [Code[20]];
        LpNo: Code[20];
        ResultObject: JsonObject;
        LpArray: JsonArray;
        FailedPrintLpArray: JsonArray;
        ResultText: Text;
        PrintedCount: Integer;
        PrintFailureCount: Integer;
    begin

        // Creation is the inventory operation. Commit it before best-effort
        // printing so an offline printer never removes the new LP records.
        // A replay deliberately does not enqueue labels again: the first call
        // may have printed successfully even if its HTTP response was lost.
        if PrintLabels and (not Replayed) then begin
            Commit();
            foreach LpNo in CreatedLpNos do begin
                LP.Get(LpNo);
                ClearLastError();
                if TryPrintPalletItemLabel(LP, PrinterId) then
                    PrintedCount += 1
                else begin
                    PrintFailureCount += 1;
                    FailedPrintLpNos.Add(LpNo);
                end;
            end;
        end;

        foreach LpNo in CreatedLpNos do
            LpArray.Add(LpNo);
        foreach LpNo in FailedPrintLpNos do
            FailedPrintLpArray.Add(LpNo);
        ResultObject.Add('createdLpNos', LpArray);
        ResultObject.Add('failedPrintLpNos', FailedPrintLpArray);
        ResultObject.Add('createdCount', CreatedLpNos.Count());
        ResultObject.Add('printedCount', PrintedCount);
        ResultObject.Add('printFailureCount', PrintFailureCount);
        ResultObject.Add('replayed', Replayed);
        ResultObject.Add('printSkippedOnReplay', Replayed and PrintLabels);
        ResultObject.Add('sourceItemLedgerEntryNo', Rec."Entry No.");
        ResultObject.Add('lpAllocatableQuantityAfter', LPMgt.AllocatableQuantityForItemLedgerEntry(Rec."Entry No."));
        ResultObject.WriteTo(ResultText);
        exit(ResultText);
    end;

    [TryFunction]
    local procedure TryPrintPalletItemLabel(var LP: Record "DOPSWHS LP Header"; PrinterId: Code[50])
    var
        Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
    begin
        Dispatcher.PrintPalletItemLabels(LP, PrinterId, 1);
    end;

    var
        BaseUnitOfMeasure: Code[10];
        AllocatedLPQuantity: Decimal;
        LPAllocatableQuantity: Decimal;
        LPManagement: Codeunit "DOPSWHS LP Management";
}
