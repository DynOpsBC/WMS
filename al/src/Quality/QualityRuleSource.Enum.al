enum 72000 "DOPSWHS Quality Rule Source"
{
    // Which posting a quality inspection rule guards (KIT-009 receipt gate,
    // INV-009 assembly final inspection).
    Extensible = true;
    Caption = 'Quality Rule Source';

    value(0; "Purchase Receipt")
    {
        Caption = 'Purchase Receipt';
    }
    value(1; "Assembly Output")
    {
        Caption = 'Assembly Output';
    }
}
