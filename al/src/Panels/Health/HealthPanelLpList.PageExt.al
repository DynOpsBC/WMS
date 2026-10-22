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
                ToolTip = 'Depodaki sorunları (LP miktarı ≠ stok, LP''nin kaynak girişi tükenmiş, LP lokasyon/göz uyuşmazlığı, negatif LP satırı, yetim LP ataması, geri alınmış mal kabulde dolu LP, takılan baskılar) tek ekranda gösterir; güvenli olanları onayla düzeltir.';
                Image = CheckList;
                RunObject = page "DOPSWHS Health Panel";
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
            }
        }
    }
}
