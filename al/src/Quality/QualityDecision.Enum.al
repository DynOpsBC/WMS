enum 72002 "DOPSWHS Quality Decision"
{
    // Disposition of a failed quality order (INV-010). Scrap and Return to
    // Vendor turn into inventory documents; Rework opens a re-inspection.
    Extensible = true;
    Caption = 'Quality Decision';

    value(0; " ")
    {
        Caption = ' ';
    }
    value(1; "Accept with Deviation")
    {
        Caption = 'Accept with Deviation';
    }
    value(2; Rework)
    {
        Caption = 'Rework';
    }
    value(3; "Return to Vendor")
    {
        Caption = 'Return to Vendor';
    }
    value(4; Scrap)
    {
        Caption = 'Scrap';
    }
}
