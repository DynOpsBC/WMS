/// <summary>
/// Packing list: one section per root container (pallet), its nested
/// containers (cartons/boxes) with SSCC and weights, and the item lines.
/// The filtered root LPs come from "DOPSWHS Packing List Mgt."; document,
/// partner and ship-to data are the LPs' own snapshot so the list prints the
/// same after the source document is posted or deleted.
/// </summary>
report 72315 "DOPSWHS Packing List"
{
    Caption = 'Paketleme Listesi';
    UsageCategory = ReportsAndAnalysis;
    ApplicationArea = All;
    DefaultLayout = RDLC;
    RDLCLayout = './src/Ship/PackingList.rdlc';

    dataset
    {
        dataitem(RootLP; "DOPSWHS LP Header")
        {
            RequestFilterFields = "No.";

            column(CompanyName; CompanyInformation.Name) { }
            column(PrintedAt; Format(CurrentDateTime(), 0, '<Day,2>.<Month,2>.<Year4> <Hours24>:<Minutes,2>')) { }
            column(DocumentNo; HeaderDocumentNo) { }
            column(DocumentTypeText; HeaderDocumentType) { }
            column(DocumentDate; HeaderDocumentDate) { }
            column(ExternalDocumentNo; HeaderExternalDocNo) { }
            column(PartnerName; HeaderPartnerName) { }
            column(ShipToName; HeaderShipToName) { }
            column(ShipToAddress; HeaderShipToAddress) { }
            column(ShipToCity; HeaderShipToCity) { }
            column(ShipmentMethod; HeaderShipmentMethod) { }
            column(ShippingAgent; HeaderShippingAgent) { }
            column(ContainerNo; HeaderContainerNo) { }
            column(SealNo; HeaderSealNo) { }
            column(PalletCount; TotalPallets) { }
            column(CartonCount; TotalCartons) { }
            column(BoxCount; TotalBoxes) { }
            column(SackCount; TotalSacks) { }
            column(OtherCount; TotalOthers) { }
            column(RootCount; TotalRoots) { }
            column(TotalNetKg; TotalNet) { }
            column(TotalGrossKg; TotalGross) { }
            column(RootLpNo; "No.") { }
            column(RootSSCC; SSCC) { }
            column(RootTemplate; "LP Template Code") { }

            dataitem(Line; Integer)
            {
                DataItemTableView = sorting(Number);

                column(EntryNo; Buffer."Entry No.") { }
                column(Level; Buffer.Level) { }
                column(RootKind; Buffer."Root Kind") { }
                column(RootNetKg; Buffer."Root Net Weight kg") { }
                column(RootGrossKg; Buffer."Root Gross Weight kg") { }
                column(RootContainerCount; Buffer."Root Container Count") { }
                column(ChildLpNo; Buffer."Child LP No.") { }
                column(ChildSSCC; Buffer."Child SSCC") { }
                column(ChildKind; Buffer."Child Kind") { }
                column(ChildNetKg; Buffer."Child Net Weight kg") { }
                column(ChildGrossKg; Buffer."Child Gross Weight kg") { }
                column(ChildDepth; Buffer."Child Depth") { }
                column(ContainerLpNo; Buffer."Container LP No.") { }
                column(ItemNo; Buffer."Item No.") { }
                column(ItemDescription; Buffer.Description) { }
                column(VariantCode; Buffer."Variant Code") { }
                column(LotNo; Buffer."Lot No.") { }
                column(SerialNo; Buffer."Serial No.") { }
                column(Quantity; Buffer.Quantity) { }
                column(UnitOfMeasure; Buffer."Unit of Measure") { }
                column(ExpirationDate; Buffer."Expiration Date") { }
                column(LineWeightKg; Buffer."Line Weight kg") { }

                trigger OnPreDataItem()
                begin
                    Buffer.Reset();
                    Buffer.SetRange("Root LP No.", RootLP."No.");
                    RowCount := Buffer.Count();
                    SetRange(Number, 1, RowCount);
                end;

                trigger OnAfterGetRecord()
                begin
                    if Number = 1 then
                        Buffer.FindSet()
                    else
                        Buffer.Next();
                end;
            }

            trigger OnPreDataItem()
            begin
                CompanyInformation.Get();
                PrepareTotals(RootLP);
            end;

            trigger OnAfterGetRecord()
            begin
                if HeaderDocumentNo = '' then
                    LoadHeader(RootLP);
            end;
        }
    }

    /// <summary>
    /// The buffer is built once for every filtered root so document totals
    /// (pallet/carton/box counts, weights) are known before the first page.
    /// </summary>
    local procedure PrepareTotals(var FilteredRoot: Record "DOPSWHS LP Header")
    var
        Root: Record "DOPSWHS LP Header";
        PackingList: Codeunit "DOPSWHS Packing List Mgt.";
        Counters: Dictionary of [Text, Integer];
        RootNet: Decimal;
        RootGross: Decimal;
        ContainerCount: Integer;
    begin
        Buffer.Reset();
        Buffer.DeleteAll();
        Root.CopyFilters(FilteredRoot);
        if Root.FindSet() then
            repeat
                PackingList.BuildForRootLp(Root, Buffer, Counters, RootNet, RootGross, ContainerCount);
                TotalRoots += 1;
                TotalNet += RootNet;
                TotalGross += RootGross;
            until Root.Next() = 0;
        TotalPallets := PackingList.KindCount(Counters, Enum::"DOPSWHS LP Container Kind"::Pallet);
        TotalCartons := PackingList.KindCount(Counters, Enum::"DOPSWHS LP Container Kind"::Carton);
        TotalBoxes := PackingList.KindCount(Counters, Enum::"DOPSWHS LP Container Kind"::Box);
        TotalSacks := PackingList.KindCount(Counters, Enum::"DOPSWHS LP Container Kind"::Sack);
        TotalOthers := PackingList.KindCount(Counters, Enum::"DOPSWHS LP Container Kind"::Tote) +
            PackingList.KindCount(Counters, Enum::"DOPSWHS LP Container Kind"::Other) +
            PackingList.KindCount(Counters, Enum::"DOPSWHS LP Container Kind"::Unspecified);
    end;

    local procedure LoadHeader(LP: Record "DOPSWHS LP Header")
    var
        PackingList: Codeunit "DOPSWHS Packing List Mgt.";
        ContainerNo: Code[30];
        SealNo: Code[30];
    begin
        HeaderDocumentNo := LP."Source Document No.";
        HeaderDocumentType := Format(LP."Source Document Type");
        if HeaderDocumentNo = '' then begin
            HeaderDocumentNo := LP."Assigned Document No.";
            HeaderDocumentType := Format(LP."Assigned Document Type");
        end;
        if HeaderDocumentNo = '' then begin
            HeaderDocumentNo := LP."No.";
            HeaderDocumentType := 'LP';
        end;
        if LP."Source Document Date" <> 0D then
            HeaderDocumentDate := Format(LP."Source Document Date", 0, '<Day,2>.<Month,2>.<Year4>');
        HeaderExternalDocNo := LP."External Document No.";
        HeaderPartnerName := LP."Partner Name";
        if LP."Partner No." <> '' then
            HeaderPartnerName := LP."Partner No." + ' · ' + LP."Partner Name";
        HeaderShipToName := LP."Ship-to Name";
        HeaderShipToAddress := LP."Ship-to Address";
        HeaderShipToCity := LP."Ship-to Post Code" + ' ' + LP."Ship-to City";
        if LP."Ship-to Country Code" <> '' then
            HeaderShipToCity += ' ' + LP."Ship-to Country Code";
        HeaderShipmentMethod := LP."Shipment Method Code";
        HeaderShippingAgent := LP."Shipping Agent Code";
        if LP."Shipping Agent Service Code" <> '' then
            HeaderShippingAgent += ' / ' + LP."Shipping Agent Service Code";
        PackingList.ResolveContainerInfo(LP, ContainerNo, SealNo);
        HeaderContainerNo := ContainerNo;
        HeaderSealNo := SealNo;
    end;

    var
        CompanyInformation: Record "Company Information";
        Buffer: Record "DOPSWHS Packing List Buffer" temporary;
        RowCount: Integer;
        HeaderDocumentNo: Text;
        HeaderDocumentType: Text;
        HeaderDocumentDate: Text;
        HeaderExternalDocNo: Text;
        HeaderPartnerName: Text;
        HeaderShipToName: Text;
        HeaderShipToAddress: Text;
        HeaderShipToCity: Text;
        HeaderShipmentMethod: Text;
        HeaderShippingAgent: Text;
        HeaderContainerNo: Text;
        HeaderSealNo: Text;
        TotalPallets: Integer;
        TotalCartons: Integer;
        TotalBoxes: Integer;
        TotalSacks: Integer;
        TotalOthers: Integer;
        TotalRoots: Integer;
        TotalNet: Decimal;
        TotalGross: Decimal;
}
