import AppKit
import PDFKit

let text = """
Project Lantern — proposal review
Fictional example for Foliance

Purpose
Create a shared reading room for a small design team. This proposal has not been approved.

Costs and dependencies
The proposed budget is EUR 18,000. Furniture accounts for EUR 8,000, lighting for EUR 6,000 and installation for EUR 4,000. Delivery depends on the supplier confirming stock. These are estimates, not purchase commitments.

Decisions and next steps
The project team recommends reviewing the proposal on 12 November 2026. No purchase has been authorized. The facilities lead will request two written quotations before a decision. The proposal does not name an individual owner or an installation deadline.

Questions to resolve
Does the lighting estimate include electrical work? What happens if the preferred supplier has no stock? Which budget will cover recurring maintenance?

Source note
This document is entirely fictional. Foliance should keep proposals, estimates and confirmed decisions distinct, and preserve the conditions attached to each amount.
"""
let view = NSTextView(frame: NSRect(x: 0,y: 0,width: 515,height: 700))
view.string = text
view.font = NSFont.systemFont(ofSize: 14)
view.textContainerInset = NSSize(width: 18,height: 18)
view.isRichText = false
let pdf = view.dataWithPDF(inside: view.bounds)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
try pdf.write(to: root.appendingPathComponent("AppStore/Sample.pdf"))
print("Created fictional sample PDF")
