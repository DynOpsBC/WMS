tableextension 50100 "WMS Location Ext" extends Location
{
    fields
    {
        field(50100; "WMS Enabled"; Boolean) { Caption = 'WMS Enabled'; DataClassification = CustomerContent; }
        field(50101; "Default Packing Policy"; Code[20])
        {
            Caption = 'Default Packing Policy';
            DataClassification = CustomerContent;
            TableRelation = "WMS Packing Policy".Code;
        }
        field(50102; "Allow LP Receiving"; Boolean) { Caption = 'Allow License Plate Receiving'; DataClassification = CustomerContent; }
        field(50103; "Allow LP Pick"; Boolean) { Caption = 'Allow License Plate Picking'; DataClassification = CustomerContent; }
    }
}
