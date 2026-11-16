tableextension 72120 "DOPSWHS Service App Area" extends "Application Area Setup"
{
    fields
    {
        // Application area tag: DOPSWHSService (spaces are dropped).
        field(72100; "DOPSWHS Service"; Boolean)
        {
            Caption = 'DynamicsOps Service';
            DataClassification = SystemMetadata;
        }
    }
}
