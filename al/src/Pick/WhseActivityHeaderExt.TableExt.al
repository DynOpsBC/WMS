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
    }
}
