/// <summary>
/// BADE (14 Eki 2026): karma palet dağıtımı. Mal kabulde birden çok ürün aynı
/// fiziksel paletlerde gelir (ör. AB.02316 + AB.02317, 4 palet). Her satır, boş
/// taslak LP'nin hangi mal kabul satırından ne kadar ve hangi lotla dolacağını
/// tutar. Taslak LP'ye ürün satırı Mal Kabulü Kaydet transaction'ında yazılır;
/// kayıt ya da iptal sonrasında bu satırlar silinir.
/// </summary>
table 72460 "DOPSWHS Receipt Mixed Alloc."
{
    Caption = 'Receipt Mixed LP Allocation';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "LP No."; Code[20])
        {
            Caption = 'LP No.';
            TableRelation = "DOPSWHS LP Header";
        }
        field(2; "Receipt Line No."; Integer)
        {
            Caption = 'Receipt Line No.';
        }
        field(3; "Receipt No."; Code[20])
        {
            Caption = 'Receipt No.';
        }
        field(10; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            TableRelation = Item;
        }
        field(11; "Variant Code"; Code[10])
        {
            Caption = 'Variant Code';
        }
        field(12; Quantity; Decimal)
        {
            Caption = 'Quantity';
            DecimalPlaces = 0 : 5;
        }
        field(13; "Unit of Measure Code"; Code[10])
        {
            Caption = 'Unit of Measure Code';
        }
        field(20; "Lot No."; Code[50])
        {
            Caption = 'Lot No.';
        }
        field(21; "Expiration Date"; Date)
        {
            Caption = 'Expiration Date';
        }
        field(30; "Distribution ID"; Guid)
        {
            Caption = 'Distribution ID';
        }
        field(31; "Pallet No."; Integer)
        {
            Caption = 'Pallet No.';
        }
    }

    keys
    {
        key(PK; "LP No.", "Receipt Line No.") { Clustered = true; }
        key(ReceiptLine; "Receipt No.", "Receipt Line No.") { }
        key(Distribution; "Distribution ID", "Pallet No.") { }
    }
}
