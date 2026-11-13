page 72010 "DOPSWHS Cycle Count Plan"
{
    // KIT-014 (Kitoko, Kas 2026): items with a phys. inventory counting period
    // (critical items), their counting status and a count sheet for the
    // selected ones. Counting periods are assigned on the item card
    // (Phys Invt Counting Period Code), as in standard Business Central.
    Caption = 'Cycle Count Plan';
    PageType = Worksheet;
    SourceTable = Item;
    SourceTableView = sorting("No.") where("Phys Invt Counting Period Code" = filter(<> ''));
    ApplicationArea = All;
    UsageCategory = Tasks;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    AboutTitle = 'Cycle count plan';
    AboutText = 'Items with a counting period are counted in cycles. Select the due items and use Create Count Sheet: the WMS count sheet contains all their bins and license plates in the location. Posting the sheet moves the items to their next counting period.';

    layout
    {
        area(Content)
        {
            group(Options)
            {
                Caption = 'Options';
                field(LocationCodeField; LocationCode)
                {
                    ApplicationArea = All;
                    Caption = 'Location Code';
                    TableRelation = Location;
                    ToolTip = 'Specifies the location to count. The inventory column shows the quantity in this location.';

                    trigger OnValidate()
                    begin
                        ApplyFilters();
                        CurrPage.Update(false);
                    end;
                }
                field(CountModeField; CountMode)
                {
                    ApplicationArea = All;
                    Caption = 'Count Mode';
                    ToolTip = 'Specifies how the count sheet is counted on the terminal. Blind hides the system quantity from the counter.';
                }
                field(DueOnlyField; DueOnly)
                {
                    ApplicationArea = All;
                    Caption = 'Show Due Items Only';
                    ToolTip = 'Specifies whether only items whose counting period has started are shown.';

                    trigger OnValidate()
                    begin
                        ApplyFilters();
                        CurrPage.Update(false);
                    end;
                }
            }
            repeater(Items)
            {
                field("No."; Rec."No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the item number.';
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the item description.';
                }
                field("Phys Invt Counting Period Code"; Rec."Phys Invt Counting Period Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the counting period of the item.';
                }
                field(DueStatus; DueStatus)
                {
                    ApplicationArea = All;
                    Caption = 'Counting Status';
                    StyleExpr = DueStyle;
                    ToolTip = 'Specifies whether the item is due or overdue for counting in its current counting period.';
                }
                field("Last Counting Period Update"; Rec."Last Counting Period Update")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the item was last counted in a counting period.';
                }
                field("Next Counting Start Date"; Rec."Next Counting Start Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the start of the next counting period.';
                }
                field("Next Counting End Date"; Rec."Next Counting End Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the end of the next counting period.';
                }
                field(Inventory; Rec.Inventory)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the inventory of the item in the selected location.';
                }
                field("Base Unit of Measure"; Rec."Base Unit of Measure")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the base unit of measure of the item.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(CreateCountSheet)
            {
                ApplicationArea = All;
                Caption = 'Create Count Sheet';
                Image = CreateDocument;
                ToolTip = 'Create a WMS count sheet for the selected items in the selected location (all bins and license plates). Posting it updates their counting periods.';

                trigger OnAction()
                var
                    Item: Record Item;
                    CountHeader: Record "DOPSWHS Count Sheet Header";
                    CycleCountMgmt: Codeunit "DOPSWHS Cycle Count Mgmt";
                    SheetNo: Code[20];
                    LinesCreated: Integer;
                begin
                    CurrPage.SetSelectionFilter(Item);
                    SheetNo := CycleCountMgmt.CreateCycleCountSheet(Item, LocationCode, CountMode, LinesCreated);
                    Message(SheetCreatedMsg, SheetNo, LinesCreated);
                    if CountHeader.Get(SheetNo) then
                        Page.Run(Page::"DOPSWHS Count Sheet Card", CountHeader);
                end;
            }
        }
        area(Navigation)
        {
            action(CountingPeriods)
            {
                ApplicationArea = All;
                Caption = 'Counting Periods';
                Image = PeriodEntries;
                RunObject = page "Phys. Invt. Counting Periods";
                ToolTip = 'Define how many times per year items of a counting period are counted.';
            }
            action(ItemCard)
            {
                ApplicationArea = All;
                Caption = 'Item Card';
                Image = Item;
                RunObject = page "Item Card";
                RunPageLink = "No." = field("No.");
                ToolTip = 'Open the item card, for example to assign a counting period.';
            }
            action(CountSheets)
            {
                ApplicationArea = All;
                Caption = 'Count Sheets';
                Image = List;
                RunObject = page "DOPSWHS Count Sheet List";
                ToolTip = 'Open the WMS count sheets.';
            }
        }
        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';
                actionref(CreateCountSheet_Promoted; CreateCountSheet) { }
            }
        }
    }

    trigger OnOpenPage()
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if LocationCode = '' then
            if Setup.Get('') then
                LocationCode := Setup."Default Location Code";
        CountMode := CountMode::Blind;
        DueOnly := true;
        ApplyFilters();
    end;

    trigger OnAfterGetRecord()
    var
        CycleCountMgmt: Codeunit "DOPSWHS Cycle Count Mgmt";
    begin
        DueStatus := CycleCountMgmt.GetDueStatus(Rec."Last Counting Period Update", Rec."Next Counting Start Date", Rec."Next Counting End Date");
        DueStyle := CycleCountMgmt.GetDueStyle(Rec."Last Counting Period Update", Rec."Next Counting Start Date", Rec."Next Counting End Date");
    end;

    local procedure ApplyFilters()
    begin
        Rec.FilterGroup(2);
        if LocationCode <> '' then
            Rec.SetRange("Location Filter", LocationCode)
        else
            Rec.SetRange("Location Filter");
        // Same rule as the standard "Calculate Counting Period": the period has started.
        if DueOnly then
            Rec.SetFilter("Next Counting Start Date", '<>%1&..%2', 0D, WorkDate())
        else
            Rec.SetRange("Next Counting Start Date");
        Rec.FilterGroup(0);
    end;

    var
        LocationCode: Code[10];
        CountMode: Enum "DOPSWHS Count Mode";
        DueOnly: Boolean;
        DueStatus: Text;
        DueStyle: Text;
        SheetCreatedMsg: Label 'Count sheet %1 was created with %2 line(s).', Comment = '%1 = count sheet no., %2 = number of lines';
}
