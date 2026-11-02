report 72093 "DOPSWHS Count Variance"
{
    Caption = 'Count Variance';
    UsageCategory = ReportsAndAnalysis;
    ApplicationArea = All;
    DefaultLayout = RDLC;
    // KIT-014 (Kitoko, Kas 2026): the report had no layout. The layout lists
    // per count sheet the system and counted quantity, variance, variance %
    // and value (base quantity x item unit cost) and marks the lines above the
    // count tolerance of Advanced WMS Setup, with the approval of the sheet.
    RDLCLayout = './src/Count/CountVariance.rdlc';

    dataset
    {
        dataitem(CountSheetHeader; "DOPSWHS Count Sheet Header")
        {
            RequestFilterFields = "No.", "Location Code";
            column(No_; "No.") { }
            column(Location_Code; "Location Code") { }
            column(CompanyName; CompanyProperty.DisplayName()) { }
            column(Status_Text; Format(Status)) { }
            column(Created_DateTime; Format("Created DateTime")) { }
            column(Posted_DateTime; Format("Posted DateTime")) { }
            column(Cycle_Count; Format("Cycle Count")) { }
            column(Tolerance_Text; ToleranceText) { }
            column(Approved_By; "Variance Approved By") { }
            column(Approved_At; Format("Variance Approved At")) { }
            column(Exceeding_Lines; ExceedingLines) { }
            column(Exceeding_Amount; ExceedingAmount) { }
            column(Total_Variance_Amount; TotalVarianceAmount) { }
            column(ReportTitleCaption; ReportTitleLbl) { }
            column(SheetCaption; SheetLbl) { }
            column(LocationCaption; LocationLbl) { }
            column(StatusCaption; StatusLbl) { }
            column(CreatedCaption; CreatedLbl) { }
            column(PostedCaption; PostedLbl) { }
            column(CycleCountCaption; CycleCountLbl) { }
            column(ToleranceCaption; ToleranceLbl) { }
            column(ApprovedByCaption; ApprovedByLbl) { }
            column(ExceedingLinesCaption; ExceedingLinesLbl) { }
            column(ExceedingAmountCaption; ExceedingAmountLbl) { }
            column(TotalVarianceAmountCaption; TotalVarianceAmountLbl) { }
            column(ItemNoCaption; ItemNoLbl) { }
            column(DescriptionCaption; DescriptionLbl) { }
            column(VariantCaption; VariantLbl) { }
            column(BinCaption; BinLbl) { }
            column(LpCaption; LpLbl) { }
            column(LotSerialCaption; LotSerialLbl) { }
            column(UomCaption; UomLbl) { }
            column(SystemQtyCaption; SystemQtyLbl) { }
            column(CountedQtyCaption; CountedQtyLbl) { }
            column(VarianceCaption; VarianceLbl) { }
            column(VariancePctCaption; VariancePctLbl) { }
            column(UnitCostCaption; UnitCostLbl) { }
            column(VarianceAmountCaption; VarianceAmountLbl) { }
            column(ExceedsCaption; ExceedsLbl) { }
            column(PageCaption; PageLbl) { }
            dataitem(CountSheetLine; "DOPSWHS Count Sheet Line")
            {
                DataItemLink = "Sheet No." = field("No.");
                DataItemTableView = sorting("Sheet No.", "Line No.");
                column(Item_No_; "Item No.") { }
                column(Bin_Code; "Bin Code") { }
                column(LP_No_; "LP No.") { }
                column(Lot_No_; "Lot No.") { }
                column(Serial_No_; "Serial No.") { }
                column(System_Qty; "System Qty") { }
                column(Counted_Qty_1; "Counted Qty 1") { }
                column(Counted_Qty_2; "Counted Qty 2") { }
                column(Counted_Qty_3; "Counted Qty 3") { }
                column(Variance; Variance) { }
                column(Line_No_; "Line No.") { }
                column(Variant_Code; "Variant Code") { }
                column(Unit_of_Measure_Code; "Unit of Measure Code") { }
                column(Item_Description; ItemDescription) { }
                column(Lot_Serial; LotSerialText) { }
                column(Counted_Qty; CountedQty) { }
                column(Variance_Pct; VariancePct) { DecimalPlaces = 0 : 2; }
                column(Unit_Cost; UnitCost) { AutoFormatType = 2; }
                column(Variance_Amount; VarianceAmount) { AutoFormatType = 1; }
                column(Exceeds_Tolerance; ExceedsText) { }

                trigger OnPreDataItem()
                begin
                    if OnlyVarianceLines then
                        SetFilter(Variance, '<>0');
                end;

                trigger OnAfterGetRecord()
                var
                    Item: Record Item;
                    ItemUnitOfMeasure: Record "Item Unit of Measure";
                    AbsVariancePct: Decimal;
                    AbsVarianceAmount: Decimal;
                    QtyPerUom: Decimal;
                begin
                    ItemDescription := '';
                    UnitCost := 0;
                    Item.SetLoadFields(Description, "Unit Cost");
                    if Item.Get("Item No.") then begin
                        ItemDescription := Item.Description;
                        QtyPerUom := 1;
                        if "Unit of Measure Code" <> '' then
                            if ItemUnitOfMeasure.Get("Item No.", "Unit of Measure Code") then
                                if ItemUnitOfMeasure."Qty. per Unit of Measure" <> 0 then
                                    QtyPerUom := ItemUnitOfMeasure."Qty. per Unit of Measure";
                        UnitCost := Item."Unit Cost" * QtyPerUom;
                    end;
                    LotSerialText := "Lot No.";
                    if "Serial No." <> '' then
                        if LotSerialText = '' then
                            LotSerialText := "Serial No."
                        else
                            LotSerialText := LotSerialText + ' / ' + "Serial No.";
                    CountedQty := "System Qty" + Variance;
                    ExceedsTolerance := false;
                    VariancePct := 0;
                    VarianceAmount := 0;
                    if Variance <> 0 then begin
                        ExceedsTolerance := CountToleranceMgmt.EvaluateVariance("Item No.", "Unit of Measure Code", "System Qty", Variance, AbsVariancePct, AbsVarianceAmount);
                        // Only flagged while a tolerance check is active in setup.
                        ExceedsTolerance := ExceedsTolerance and ToleranceActive;
                        if Variance < 0 then begin
                            VariancePct := -AbsVariancePct;
                            VarianceAmount := -AbsVarianceAmount;
                        end else begin
                            VariancePct := AbsVariancePct;
                            VarianceAmount := AbsVarianceAmount;
                        end;
                    end;
                    if ExceedsTolerance then
                        ExceedsText := ExceedsYesTxt
                    else
                        ExceedsText := '';
                end;
            }

            trigger OnAfterGetRecord()
            var
                ToleranceCheck: Enum "DOPSWHS Count Tolerance Check";
                TolerancePct: Decimal;
                ToleranceAmount: Decimal;
            begin
                CountToleranceMgmt.GetToleranceSetup(ToleranceCheck, TolerancePct, ToleranceAmount);
                ToleranceActive := ToleranceCheck <> ToleranceCheck::Disabled;
                if ToleranceActive then
                    ToleranceText := StrSubstNo(ToleranceActiveTxt, ToleranceCheck, CountToleranceMgmt.ToleranceText(TolerancePct, ToleranceAmount))
                else
                    ToleranceText := StrSubstNo(ToleranceDisabledTxt, CountToleranceMgmt.ToleranceText(TolerancePct, ToleranceAmount));
                CountToleranceMgmt.GetSheetSummary("No.", ExceedingLines, ExceedingAmount, TotalVarianceAmount);
                if not ToleranceActive then begin
                    ExceedingLines := 0;
                    ExceedingAmount := 0;
                end;
            end;
        }
    }

    requestpage
    {
        SaveValues = true;

        layout
        {
            area(Content)
            {
                group(Options)
                {
                    Caption = 'Options';
                    field(OnlyVarianceLinesField; OnlyVarianceLines)
                    {
                        ApplicationArea = All;
                        Caption = 'Only Lines with Variance';
                        ToolTip = 'Specifies whether only count lines with a variance are printed.';
                    }
                }
            }
        }
    }

    var
        CountToleranceMgmt: Codeunit "DOPSWHS Count Tolerance Mgmt";
        OnlyVarianceLines: Boolean;
        ExceedsTolerance: Boolean;
        ToleranceActive: Boolean;
        ItemDescription: Text[100];
        LotSerialText: Text;
        ExceedsText: Text;
        ToleranceText: Text;
        CountedQty: Decimal;
        VariancePct: Decimal;
        UnitCost: Decimal;
        VarianceAmount: Decimal;
        ExceedingLines: Integer;
        ExceedingAmount: Decimal;
        TotalVarianceAmount: Decimal;
        ReportTitleLbl: Label 'Count Variance';
        SheetLbl: Label 'Count Sheet';
        LocationLbl: Label 'Location';
        StatusLbl: Label 'Status';
        CreatedLbl: Label 'Created';
        PostedLbl: Label 'Posted';
        CycleCountLbl: Label 'Cycle Count';
        ToleranceLbl: Label 'Count Tolerance';
        ApprovedByLbl: Label 'Variance Approved By';
        ExceedingLinesLbl: Label 'Lines above Tolerance';
        ExceedingAmountLbl: Label 'Value above Tolerance (LCY)';
        TotalVarianceAmountLbl: Label 'Total Variance Value (LCY)';
        ItemNoLbl: Label 'Item No.';
        DescriptionLbl: Label 'Description';
        VariantLbl: Label 'Variant';
        BinLbl: Label 'Bin';
        LpLbl: Label 'LP No.';
        LotSerialLbl: Label 'Lot / Serial No.';
        UomLbl: Label 'Unit';
        SystemQtyLbl: Label 'System Qty.';
        CountedQtyLbl: Label 'Counted Qty.';
        VarianceLbl: Label 'Variance';
        VariancePctLbl: Label 'Variance %';
        UnitCostLbl: Label 'Unit Cost';
        VarianceAmountLbl: Label 'Variance Value';
        ExceedsLbl: Label 'Above Tolerance';
        PageLbl: Label 'Page';
        ExceedsYesTxt: Label 'Yes';
        ToleranceActiveTxt: Label '%1, %2', Comment = '%1 = tolerance check (Warning / Approval Required), %2 = tolerance values';
        ToleranceDisabledTxt: Label 'Disabled (%1)', Comment = '%1 = tolerance values';
}
