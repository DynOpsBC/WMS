page 72081 "DOPSWHS Warehouse Manager RC"
{
    Caption = 'Warehouse Manager';
    PageType = RoleCenter;
    ApplicationArea = All;

    layout
    {
        area(RoleCenter)
        {
            part(Activities; "DOPSWHS Warehouse Manager Act")
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        area(Sections)
        {
            group(Shortcuts)
            {
                Caption = 'Shortcuts';
                action(Receipts) { Caption = 'Receipts'; ApplicationArea = All; RunObject = page "Warehouse Receipt List"; }
                action(Picks) { Caption = 'Picks'; ApplicationArea = All; RunObject = page "Warehouse Picks"; }
                action(Shipments) { Caption = 'Shipments'; ApplicationArea = All; RunObject = page "Warehouse Shipment List"; }
                action(CountSheets) { Caption = 'Count Sheets'; ApplicationArea = All; RunObject = page "DOPSWHS Count Sheet List"; }
                action(LPBrowser) { Caption = 'LP Browser'; ApplicationArea = All; RunObject = page "DOPSWHS LP List"; }
            }
        }
    }
}
