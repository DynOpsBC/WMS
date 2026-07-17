page 72347 "DOPSWHS Packer RC"
{
    // ELOG paketleme istasyonu operatörü rolü. Üç worksheet butonu üst
    // navigasyonda (Embedding) görünür; ana ekranda ayrıca 3 tıklanabilir
    // sayaç kutusu vardır (Packer Activities). El terminali aynı Pack
    // Session tablolarına yazar — terminalden açılan oturumlar buradaki
    // sayaçlarda ve Pack Sessions listesinde canlı görünür.
    Caption = 'Packer';
    PageType = RoleCenter;
    ApplicationArea = All;

    layout
    {
        area(RoleCenter)
        {
            part(Activities; "DOPSWHS Packer Activities")
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        area(Embedding)
        {
            action(BatchWorksheet)
            {
                Caption = 'Batch Package Worksheet';
                ApplicationArea = All;
                RunObject = page "DOPSWHS Pack Station Bulk";
            }
            action(MonoSkuWorksheet)
            {
                Caption = 'Mono-SKU Package Worksheet';
                ApplicationArea = All;
                RunObject = page "DOPSWHS Mono-SKU Pack Station";
            }
            action(SoloWorksheet)
            {
                Caption = 'Solo Package Worksheet';
                ApplicationArea = All;
                RunObject = page "DOPSWHS Pack Station Solo";
            }
        }
        area(Sections)
        {
            group(Packing)
            {
                Caption = 'Packing';
                action(BatchWorksheetNav) { Caption = 'Batch Package Worksheet'; ApplicationArea = All; RunObject = page "DOPSWHS Pack Station Bulk"; }
                action(MonoSkuWorksheetNav) { Caption = 'Mono-SKU Package Worksheet'; ApplicationArea = All; RunObject = page "DOPSWHS Mono-SKU Pack Station"; }
                action(SoloWorksheetNav) { Caption = 'Solo Package Worksheet'; ApplicationArea = All; RunObject = page "DOPSWHS Pack Station Solo"; }
                action(PackSessions) { Caption = 'Pack Sessions (All)'; ApplicationArea = All; RunObject = page "DOPSWHS Pack Session List"; }
                action(ToteAssignments) { Caption = 'Pick Tote Assignments'; ApplicationArea = All; RunObject = page "DOPSWHS Pick Tote Assignments"; }
            }
        }
    }
}
