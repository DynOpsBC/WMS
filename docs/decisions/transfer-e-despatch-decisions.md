# Transfer e-İrsaliye Decisions

Scope: Turkish e-İrsaliye (UBL-TR DespatchAdvice) for transfer orders, direct transfers, warehouse
movements, inventory movements and handheld bin-to-bin moves, including subcontracting (fason) and
consignment shipments. Companion documents: `docs/transfer-e-despatch.md` (operator flow and API) and
`TR-e-Transformation/bc-extension/connector-wms/README.md` (connector).

## ADR-TED-001: e-Transformation Owns the Legal Document

The DynOpsEtrans app is the only producer of e-documents. It owns the receiver setup (location and bin
receiver map), the source policies, the UBL party mapping, the integrator calls (Turkcell/Sovos), the
official PDF and the 80mm thermal template. DynOpsEtrans works without BCWMSApp.

## ADR-TED-002: WMS Keeps a Provider-Agnostic Request Mirror

BCWMSApp does not reference DynOpsEtrans. It records each handheld e-despatch request in table
`DOPSWHS EDesp Request` (72453) and publishes integration events from codeunit
`DOPSWHS EDesp Request Mgt` (72455). Without a subscriber a request ends in `WaitingAdapter`, the stock
posting is never rolled back, and the fallback `Transfer Sevk Fişi` report (72377 A4 / 72378 80mm) can
be printed with the text "e-İrsaliye değildir".

The existing subcontract outbox `DOPSWHS Subcontract EDesp Out` (72449) cannot be generalised because
its key on `Posted Transfer Shipment No.` is unique. It is kept for existing rows, marked
`ObsoleteState = Pending`, and new fason shipments create request rows instead.

## ADR-TED-003: A Separate Connector App Is the Only Bridge

`DynOps WMS e-Despatch Connector` (TR-e-Transformation repo, `bc-extension/connector-wms/`, IDs
78950-78989, tests 78990-78999) depends on both apps, subscribes to the WMS request events and calls
the public facade `DYN Despatch Facade` (78365). It also mirrors e-Transformation status changes back
to the WMS request and resolves the fason receiver (subcontractor vendor). The connector targets
platform 27 / runtime 16 because DynOpsEtrans does; BCWMSApp itself stays on platform 24 / runtime 13.

## ADR-TED-004: Draft, Review, Send, Print

Posting or registering only queues the e-despatch. The draft is built after the commit, the operator
can change receiver, address, vehicle, driver and note on the handheld or in BC, and only then sends
and prints. A document stays editable until the integrator owns it (Sending, Sent, Delivered,
Accepted, Rejected, Cancelled, Archived are locked). Automatic send is an opt-in per source type in
`DYN Despatch Source Policy`.

## ADR-TED-005: Receiver Resolution Order

Explicit value on the document > event subscriber (for example fason) > bin map (target bin) >
location map (target location) > own company. Movements inside one location to an unmapped bin, or
from a mapped bin back to an own bin, do not create an e-despatch; the skip reason is logged on the
automation entry.

## ADR-TED-006: Printing

A4: the integrator PDF (official copy after send) or the render-service preview (watermarked draft).
80mm: the e-Transformation XSLT template with usage `PrintThermal80`, rendered to PDF by the
render-service with `paper = THERMAL80`. Both go through `DOPSWHS Print Dispatcher.PrintPdf` to the
device printer mapped for usage `EDespatch` (11) or `EDespatchThermal` (12). Thermal printers are set
up as PDF printers behind the print agent or PrintNode.

## ADR-TED-007: Object ID Pressure

The new WMS objects use the free block 72453-72478 and enum IDs 72214-72218, which are outside the
Sprint 0 baseline `72000-72099` but inside the declared `72200-72489` range. The remaining free WMS
range is small (72377-72399 and parts of 72300-72325). Any further e-despatch work should plan the
documented expansion to `72000-72499` or move objects to the connector.

The DynOpsEtrans manifest range is narrowed from 78000-78999 to 78000-78899 so the test app
(78900-78949) and the connector (78950-78999) no longer overlap it. No DynOpsEtrans object used an ID
at or above 78850.
