enum 72003 "DOPSWHS Count Tolerance Check"
{
    // What happens when a count variance exceeds the tolerance (KIT-014).
    Extensible = true;
    Caption = 'Count Tolerance Check';

    value(0; Disabled)
    {
        Caption = 'Disabled';
    }
    value(1; Warning)
    {
        Caption = 'Warning';
    }
    value(2; "Approval Required")
    {
        Caption = 'Approval Required';
    }
}
