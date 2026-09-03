tableextension 72426 "DOPSWHS Item Ledger Entry Ext" extends "Item Ledger Entry"
{
    fields
    {
        field(72428; "DOPSWHS LP No."; Code[20])
        {
            Caption = 'LP No.';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Header"."No.";
        }
        field(72429; "DOPSWHS LP Nos."; Text[250])
        {
            // NEDEN: 72428 tek bir LP'ye TableRelation ile bağlı; birden fazla
            // paletten toplanan bir satışta yalnız ilk palet görünüyor ve kayıt
            // yanıltıcı oluyordu (BADE saha bildirimi). Bu alan TÜKETİLEN TÜM
            // paletleri tüketim sırasına göre virgülle ayırarak taşır.
            // KURAL: yalnız BİRDEN FAZLA palet tüketildiğinde doldurulur; tek
            // palet tüketildiğinde boş kalır (tek palet zaten "LP No." alanında).
            Caption = 'LP No.leri';
            DataClassification = CustomerContent;
            Editable = false;
        }
    }
}
