tableextension 50029002 "OSD Item Ext" extends Item
{
    fields
    {
        field(50029000; "WMS Catch Weight"; Boolean) { Caption = 'WMS Catch Weight'; DataClassification = CustomerContent; }
        field(50029001; "WMS Hazmat Class"; Code[10]) { Caption = 'WMS Hazmat Class'; DataClassification = CustomerContent; }
        field(50029002; "WMS FEFO Required"; Boolean) { Caption = 'WMS FEFO Required'; DataClassification = CustomerContent; }
    }
}
