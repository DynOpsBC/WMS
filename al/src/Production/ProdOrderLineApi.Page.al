page 72233 "DOPSWHS Prod Order Line API"
{
    // Output is posted only through explicit, retry-safe bound actions.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'productionOrderLine';
    EntitySetName = 'productionOrderLines';
    SourceTable = "Prod. Order Line";
    SourceTableView = where(Status = filter(Released | Finished));
    ODataKeyFields = Status, "Prod. Order No.", "Line No.";
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
                field(status; Rec.Status) { Caption = 'status'; }
                field(prodOrderNo; Rec."Prod. Order No.") { Caption = 'prodOrderNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(itemNo; Rec."Item No.") { Caption = 'itemNo'; }
                field(variantCode; Rec."Variant Code") { Caption = 'variantCode'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(quantity; Rec.Quantity) { Caption = 'quantity'; }
                field(finishedQuantity; Rec."Finished Quantity") { Caption = 'finishedQuantity'; }
                field(remainingQuantity; Rec."Remaining Quantity") { Caption = 'remainingQuantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(binCode; Rec."Bin Code") { Caption = 'binCode'; }
                field(lotRequired; LotRequired) { }
                field(serialRequired; SerialRequired) { }
                field(expirationRequired; ExpirationRequired) { }
                field(workDate; WorkDate()) { }
                field(dueDate; Rec."Due Date") { Caption = 'dueDate'; }
            }
        }
    }

    trigger OnOpenPage()
    var
        Filters: Codeunit "DOPSWHS App Role Filter Mgmt";
        Ref: RecordRef;
    begin
        Rec.FilterGroup(2);
        Ref.GetTable(Rec);
        Filters.ApplyForCurrentUser(Ref, Enum::"DOPSWHS App Filter Entity"::ProductionOrderLine);
        Ref.SetTable(Rec);
        Rec.FilterGroup(0);
    end;
    trigger OnAfterGetRecord()
    var
        Item: Record Item;
        Tracking: Record "Item Tracking Code";
    begin
        Clear(LotRequired);
        Clear(SerialRequired);
        Clear(ExpirationRequired);
        if Item.Get(Rec."Item No.") then
            if (Item."Item Tracking Code" <> '') and Tracking.Get(Item."Item Tracking Code") then begin
                LotRequired := Tracking."Lot Specific Tracking" or Tracking."Lot Pos. Adjmt. Inb. Tracking";
                SerialRequired := Tracking."SN Specific Tracking" or Tracking."SN Pos. Adjmt. Inb. Tracking";
                ExpirationRequired := Tracking."Man. Expir. Date Entry Reqd.";
            end;
    end;
    [ServiceEnabled]
    procedure prepareOutput(quantity: Decimal; postingDate: Date; binCode: Code[20]; expirationDate: Date; requestId: Guid): Text
    var
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
    begin
        Rec.TestField(Status, Rec.Status::Released);
        exit(Mgmt.PrepareOutput(Rec, quantity, postingDate, binCode, expirationDate, requestId));
    end;

    /// <summary>Aynı lotla parçalı çıktı; lotNo boşsa yeni lot atanır.</summary>
    [ServiceEnabled]
    procedure prepareOutputWithLot(quantity: Decimal; postingDate: Date; binCode: Code[20]; expirationDate: Date; requestId: Guid; lotNo: Code[50]): Text
    var
        Mgmt: Codeunit "DOPSWHS Partial Output Mgmt";
    begin
        Rec.TestField(Status, Rec.Status::Released);
        exit(Mgmt.PrepareOutputWithLot(Rec, quantity, postingDate, binCode, expirationDate, requestId, lotNo));
    end;

    /// <summary>
    /// DKC: emrin çıktı gözündeki kutu LP'lerini palete koyar. palletLpNo boşsa
    /// templateCode ile yeni palet kurulur. Sonuç JSON (palletLpNo, boxCount...).
    /// </summary>
    [ServiceEnabled]
    procedure palletizeOutput(templateCode: Code[20]; palletLpNo: Code[20]): Text
    var
        Pallet: Codeunit "DOPSWHS Output Pallet Mgmt";
    begin
        exit(Pallet.PalletizeOutput(Rec, templateCode, palletLpNo));
    end;

    /// <summary>DKC: palete konabilecek kutu LP'leri (JSON dizi).</summary>
    [ServiceEnabled]
    procedure listOutputBoxes(): Text
    var
        Pallet: Codeunit "DOPSWHS Output Pallet Mgmt";
    begin
        exit(Pallet.ListOutputBoxes(Rec));
    end;

    /// <summary>DKC: yalnız seçilen kutu LP'lerini (virgülle ayrılmış) palete koyar.</summary>
    [ServiceEnabled]
    procedure palletizeOutputBoxes(templateCode: Code[20]; palletLpNo: Code[20]; boxLpNos: Text): Text
    var
        Pallet: Codeunit "DOPSWHS Output Pallet Mgmt";
    begin
        exit(Pallet.PalletizeOutputBoxes(Rec, templateCode, palletLpNo, boxLpNos));
    end;
    var
        LotRequired: Boolean;
        SerialRequired: Boolean;
        ExpirationRequired: Boolean;
}
