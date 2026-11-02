pageextension 72005 "DOPSWHS Item Reclass Jnl Ctrl" extends "Item Reclass. Journal"
{
    // KIT-015 (Kitoko, Kas 2026): the reason code column is hidden in the
    // standard page; it is shown when Setup makes it mandatory.
    layout
    {
        modify("Reason Code")
        {
            Visible = ReasonCodeMandatory;
        }
    }

    trigger OnOpenPage()
    var
        ReclassControl: Codeunit "DOPSWHS Reclass Control";
        PostingRestricted: Boolean;
    begin
        ReclassControl.GetReclassSetup(ReasonCodeMandatory, PostingRestricted);
    end;

    var
        ReasonCodeMandatory: Boolean;
}
