tableextension 72449 "DOPSWHS Regd Whse Act Line" extends "Registered Whse. Activity Line"
{
    fields
    {
        // Same number, name and type as field 72403 on tableextension 72403
        // "DOPSWHS Whse Activity Line" (Warehouse Activity Line). BC's
        // Whse.-Activity-Register builds the registered line with TransferFields,
        // so the LP scanned or stamped on the pick Take line survives registration
        // here. DOPSWHS LP Propagation reads it after a sales shipment posts to
        // reduce exactly the pallet(s) the pick physically took, even when the
        // shipment line itself carried no LP.
        // Historic row: no TableRelation on purpose, the LP may be deleted later.
        field(72403; "LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }
}
