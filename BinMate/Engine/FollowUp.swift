import Foundation

/// One targeted question, asked when answering it would actually change the verdict.
///
/// The app already had a way to fix thin data: open the manual picker and describe the
/// packaging. That is a form, and a form is what you offer when you have no idea what is
/// missing. Here the app usually does know — a lone bottle almost certainly has a cap, a
/// material it cannot recognise is the one thing blocking a real answer — so it can ask
/// one question instead of presenting an empty table.
///
/// Questions are only generated where the answer matters. Asking about a label on a
/// product already carrying three well-described parts would be pestering.
struct FollowUpQuestion: Identifiable, Sendable {
    enum Effect: Sendable {
        /// Add a part the record is missing.
        case add(PackagingComponent)
        /// Replace the material of a part already listed.
        case setMaterial(componentID: UUID, material: TaxonomyID)
        /// The user says there is nothing to add.
        case decline
    }

    struct Option: Identifiable, Sendable {
        var id: String
        var label: String
        var effect: Effect
    }

    var id: String
    var prompt: String
    /// Why this is being asked, so it does not read as an interrogation.
    var rationale: String
    var options: [Option]
}

enum FollowUp {
    /// Materials worth offering for a given part, commonest first.
    ///
    /// Short lists on purpose: three plausible answers and an escape hatch beats a
    /// nineteen-row picker when the point is to ask a quick question.
    private static let likelyMaterials: [TaxonomyID: [TaxonomyID]] = [
        "en:lid-or-cap": ["en:pp-5-polypropylene", "en:hdpe-2-high-density-polyethylene", "en:aluminium"],
        "en:lid": ["en:aluminium", "en:pp-5-polypropylene", "en:cardboard"],
        "en:label": ["en:paper", "en:ldpe-4-low-density-polyethylene", "en:coated-paper"],
        "en:bottle": ["en:pet-1-polyethylene-terephthalate", "en:clear-glass", "en:hdpe-2-high-density-polyethylene"],
        "en:jar": ["en:clear-glass", "en:pp-5-polypropylene"],
        "en:can": ["en:aluminium", "en:steel"],
        "en:pot": ["en:ps-6-polystyrene", "en:pp-5-polypropylene"],
        "en:film": ["en:ldpe-4-low-density-polyethylene", "en:o-7-other-plastics"],
        "en:sleeve": ["en:cardboard", "en:ldpe-4-low-density-polyethylene"],
        "en:seal": ["en:aluminium", "en:ldpe-4-low-density-polyethylene"],
    ]

    /// Parts a container of this shape usually has, and the app should ask about when
    /// the record lists only the container itself.
    private static let usualCompanions: [TaxonomyID: [TaxonomyID]] = [
        "en:bottle": ["en:lid-or-cap", "en:label"],
        "en:jar": ["en:lid", "en:label"],
        "en:pot": ["en:lid", "en:sleeve"],
        "en:can": ["en:label"],
    ]

    /// At most this many, because the point is a question, not a questionnaire.
    static let limit = 3

    static func questions(for product: ScannedProduct) -> [FollowUpQuestion] {
        var questions: [FollowUpQuestion] = []
        let presentShapes = Set(product.components.compactMap(\.shape))

        // 1. A material the taxonomy cannot place blocks a real answer entirely, so it
        //    outranks anything else worth asking.
        for component in product.components where !MaterialTaxonomy.isKnown(component.material) {
            let candidates = component.shape.flatMap { likelyMaterials[$0] }
                ?? ["en:o-7-other-plastics", "en:paper", "en:metal"]

            questions.append(
                FollowUpQuestion(
                    id: "material-\(component.id)",
                    prompt: "What is the \(component.shapeName.lowercased()) made of?",
                    rationale: "The record says “\(component.material.humanized)”, which BinMate cannot place. Without this it falls back to the default bin.",
                    options: candidates.map { material in
                        FollowUpQuestion.Option(
                            id: material.value,
                            label: MaterialTaxonomy.displayName(for: material),
                            effect: .setMaterial(componentID: component.id, material: material)
                        )
                    } + [
                        FollowUpQuestion.Option(id: "skip", label: "Not sure", effect: .decline)
                    ]
                )
            )
        }

        // 2. A container listed on its own is almost certainly missing its lid and label.
        //    Only asked where the record is genuinely thin — a product with several
        //    well-described parts gets left alone.
        if product.components.count <= 2 {
            for component in product.components {
                guard let shape = component.shape,
                      let companions = usualCompanions[shape] else { continue }

                for companion in companions where !presentShapes.contains(companion) {
                    let materials = likelyMaterials[companion] ?? ["en:o-7-other-plastics"]
                    questions.append(
                        FollowUpQuestion(
                            id: "companion-\(companion.value)",
                            prompt: "Does it have a \(ShapeTaxonomy.displayName(for: companion).lowercased())?",
                            rationale: "The record lists only \(product.components.count) part\(product.components.count == 1 ? "" : "s"). A \(ShapeTaxonomy.displayName(for: shape).lowercased()) usually has one, and it often goes in a different bin.",
                            options: materials.map { material in
                                FollowUpQuestion.Option(
                                    id: material.value,
                                    label: "Yes — \(MaterialTaxonomy.displayName(for: material))",
                                    effect: .add(PackagingComponent(shape: companion, material: material))
                                )
                            } + [
                                FollowUpQuestion.Option(id: "no", label: "No", effect: .decline)
                            ]
                        )
                    )
                }
            }
        }

        // 3. A part with no shape at all cannot benefit from any shape-specific rule,
        //    which is where deposits and drop-offs live.
        for component in product.components where component.shape == nil {
            let shapes: [TaxonomyID] = ["en:bottle", "en:can", "en:box", "en:bag"]
            questions.append(
                FollowUpQuestion(
                    id: "shape-\(component.id)",
                    prompt: "Which part is the \(component.materialName.lowercased())?",
                    rationale: "Knowing the part matters: deposits and drop-off rules are written for specific shapes.",
                    options: shapes.map { shape in
                        FollowUpQuestion.Option(
                            id: shape.value,
                            label: ShapeTaxonomy.displayName(for: shape),
                            effect: .add(PackagingComponent(shape: shape, material: component.material))
                        )
                    } + [
                        FollowUpQuestion.Option(id: "skip", label: "Not sure", effect: .decline)
                    ]
                )
            )
        }

        return Array(questions.prefix(limit))
    }

    /// Applies an answer, returning the product as it now stands.
    static func apply(_ effect: FollowUpQuestion.Effect, to product: ScannedProduct) -> ScannedProduct {
        var updated = product
        switch effect {
        case .decline:
            break
        case .add(let component):
            updated.components.append(component)
        case .setMaterial(let componentID, let material):
            guard let index = updated.components.firstIndex(where: { $0.id == componentID }) else { break }
            updated.components[index].material = MaterialTaxonomy.canonical(material)
        }
        return updated
    }
}
