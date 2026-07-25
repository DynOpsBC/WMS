permissionset 72000 "DOPSWHS-SVCTECH"
{
    // NOT: Bu obje bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    //
    // SM-10: saha servis teknisyeni için dar kapsamlı rol — depo/mal kabul/sevkiyat
    // objelerine erişimi yok, sadece Servis Yönetimi modülü. Karantina serbest bırakma
    // gibi hassas kalite aksiyonları (bkz. GKK) bu sette YOK, o "DOPSWHS-ADMIN"da kalıyor.
    Assignable = true;
    Caption = 'WMS Service Technician';

    Permissions =
        tabledata "DOPSWHS Service Asset" = R,
        tabledata "DOPSWHS Service Contract" = R,
        tabledata "DOPSWHS Service SLA" = R,
        tabledata "DOPSWHS Maintenance Plan" = RM,
        tabledata "DOPSWHS Work Order" = RIMD,
        tabledata "DOPSWHS Work Order Line" = RIMD,
        tabledata "DOPSWHS Fault Code" = R,
        codeunit "DOPSWHS Work Order Svc" = X,
        codeunit "DOPSWHS Breakdown Svc" = X,
        page "DOPSWHS Service Assets" = X,
        page "DOPSWHS Service Asset Card" = X,
        page "DOPSWHS Maintenance Plans" = X,
        page "DOPSWHS Maintenance Plan Card" = X,
        page "DOPSWHS Work Orders" = X,
        page "DOPSWHS Work Order Card" = X,
        page "DOPSWHS Work Order Subform" = X,
        page "DOPSWHS Fault Codes" = X;
}
