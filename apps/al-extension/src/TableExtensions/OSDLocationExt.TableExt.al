tableextension 50029000 "OSD Location Ext" extends Location
{
    fields
    {
        field(50029000; "WMS Enabled"; Boolean) { Caption = 'WMS Enabled'; DataClassification = CustomerContent; }
        field(50029001; "Default Packing Policy"; Code[20])
        {
            Caption = 'Default Packing Policy';
            DataClassification = CustomerContent;
            TableRelation = "OSD Packing Policy".Code;
        }
        field(50029002; "Allow LP Receiving"; Boolean) { Caption = 'Allow License Plate Receiving'; DataClassification = CustomerContent; }
        field(50029003; "Allow LP Pick"; Boolean) { Caption = 'Allow License Plate Picking'; DataClassification = CustomerContent; }
    }
}
