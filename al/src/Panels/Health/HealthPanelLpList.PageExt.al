/// <summary>
/// Depo Sağlık Paneli girişi: LP listesinden tek tıkla açılır
/// (ayrıca "Tell me" araması: Depo Sağlık, Sorun Merkezi).
/// </summary>
pageextension 72390 "DOPSWHS Health Panel LP List" extends "DOPSWHS LP List"
{
    actions
    {
        addfirst(Processing)
        {
            action(DOPSWHSOpenHealthPanel)
            {
                ApplicationArea = All;
                Caption = 'Depo Sağlık Paneli';
                ToolTip = 'Depo sorunlarını listeler.';
                Image = CheckList;
                RunObject = page "DOPSWHS Health Panel";
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
            }
        }
    }
}
