tableextension 72002 "DOPSWHS Item Jnl. Batch Ctrl" extends "Item Journal Batch"
{
    // KIT-015: batches that the WMS itself fills and posts (terminal bin moves,
    // LP location moves). Reclassification controls apply to journals people
    // post; these system batches are exempt so terminal flows keep working.
    fields
    {
        field(72004; "DOPSWHS System Batch"; Boolean)
        {
            Caption = 'WMS System Batch';
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }
}
