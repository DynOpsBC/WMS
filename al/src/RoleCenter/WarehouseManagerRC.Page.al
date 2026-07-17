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
                action(Receipts) { Caption = 'Receipts'; ApplicationArea = All; RunObject = page "Warehouse Receipts"; }
                action(Picks) { Caption = 'Picks'; ApplicationArea = All; RunObject = page "Warehouse Picks"; }
                action(Shipments) { Caption = 'Shipments'; ApplicationArea = All; RunObject = page "Warehouse Shipment List"; }
                action(CountSheets) { Caption = 'Count Sheets'; ApplicationArea = All; RunObject = page "DOPSWHS Count Sheet List"; }
                action(LPBrowser) { Caption = 'LP Browser'; ApplicationArea = All; RunObject = page "DOPSWHS LP List"; }
                // ELOG paketleme hattı — ana dashboard'da 3 ayrı bölüm (ayrıca
                // Activities part'ındaki "Pack Station" cuegroup'unda da var).
                action(PackStationSolo) { Caption = 'Solo Package Worksheet'; ApplicationArea = All; RunObject = page "DOPSWHS Pack Station Solo"; }
                action(PackStationBulk) { Caption = 'Batch Package Worksheet'; ApplicationArea = All; RunObject = page "DOPSWHS Pack Station Bulk"; }
                action(PackStationMonoSku) { Caption = 'Mono-SKU Package Worksheet'; ApplicationArea = All; RunObject = page "DOPSWHS Mono-SKU Pack Station"; }
                action(PackSessions) { Caption = 'Pack Sessions (All)'; ApplicationArea = All; RunObject = page "DOPSWHS Pack Session List"; }
                action(ToteAssignments) { Caption = 'Pick Tote Assignments'; ApplicationArea = All; RunObject = page "DOPSWHS Pick Tote Assignments"; }
            }
        }
    }
}
