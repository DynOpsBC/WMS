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

    procedure BuildZpl(var LP: Record "DOPSWHS LP Header"): Text
    var
        LPLine: Record "DOPSWHS LP Line";
        Summary: Text;
    begin
        LPLine.SetRange("LP No.", LP."No.");
        if LPLine.FindSet() then
            repeat
                Summary += StrSubstNo('%1 %2 %3\&', LPLine."Item No.", LPLine.Quantity, LPLine."Unit of Measure");
            until LPLine.Next() = 0;
        exit(
            '^XA' +
            '^FO40,30^A0N,36,36^FDLP ' + LP."No." + '^FS' +
            '^FO40,80^BY3^BCN,100,Y,N,N^FD>;00' + LP.SSCC + '^FS' +
            '^FO40,210^A0N,28,28^FD' + LP."Location Code" + ' / ' + LP."Bin Code" + '^FS' +
            '^FO40,250^A0N,24,24^FD' + CopyStr(Summary, 1, 80) + '^FS' +
            '^FO40,320^A0N,24,24^FD' + Format(LP."Built DateTime") + ' ' + Format(LP."Weight kg") + 'kg ' + Format(LP."Length cm") + 'x' + Format(LP."Width cm") + 'x' + Format(LP."Height cm") + '^FS' +
            '^XZ');
    end;
}
