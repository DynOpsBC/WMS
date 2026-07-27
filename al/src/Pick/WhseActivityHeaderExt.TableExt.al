tableextension 72429 "DOPSWHS Whse Activity Hdr Ext" extends "Warehouse Activity Header"
{
    fields
    {
        // Terminal pick listesi bu alana göre Multi/Bulk/Batch sekmelerine
        // ayrılır. MultiOrderPick.CreateGroupedPick oluşturduğu pick'e damgalar.
        field(72400; "DOPSWHS Pick Mode"; Enum "DOPSWHS Pick Mode")
        {
            Caption = 'Pick Mode (WMS)';
            DataClassification = CustomerContent;
        }
        // ELOG: aracı ekran başındaki sorumlu (masa) girer; terminaldeki
        // toplayıcı sadece görür. Toplama başlığında tutulur.
        field(72401; "DOPSWHS Vehicle No."; Code[20])
        {
            Caption = 'Vehicle No. (WMS)';
            DataClassification = CustomerContent;
        }
    }
}
