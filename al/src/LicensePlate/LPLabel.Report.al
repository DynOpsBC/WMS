report 72091 "DOPSWHS LP Label"
{
    Caption = 'LP Label';
    UsageCategory = None;
    DefaultLayout = RDLC;
    RDLCLayout = './LPLabel.rdlc';

    dataset
    {
        dataitem(LP; "DOPSWHS LP Header")
        {
            column(No_; "No.") { }
            column(SSCC; SSCC) { }
            column(Location_Code; "Location Code") { }
            column(Bin_Code; "Bin Code") { }
            column(Built_DateTime; "Built DateTime") { }
            column(Weight_kg; "Weight kg") { }
            column(Length_cm; "Length cm") { }
            column(Width_cm; "Width cm") { }
            column(Height_cm; "Height cm") { }
            column(ZplText; BuildZpl(LP)) { }
        }
    }

    /// <summary>
    /// The ZPL comes from the LP template's design (codeunit "DOPSWHS LP
    /// Label Builder"): standard, pallet, carton, box or sack, with or without
    /// the contents listed. Kept here so existing callers and the ZplText
    /// column keep working.
    /// </summary>
    procedure BuildZpl(var LP: Record "DOPSWHS LP Header"): Text
    var
        Builder: Codeunit "DOPSWHS LP Label Builder";
    begin
        exit(Builder.BuildZpl(LP));
    end;
}
