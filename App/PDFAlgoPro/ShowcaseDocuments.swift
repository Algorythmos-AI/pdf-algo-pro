#if DEBUG
  import Foundation

  /// Synthetic documents for the App Store screenshots (`-seed-library showcase`, Debug builds only).
  ///
  /// An invoice, a lease and a quarterly report, in the device's language (English, or French when it
  /// is set to French), so the French screenshots show French documents. Every name is fictional,
  /// in the style of the sample's "Example" and "Sample" (AGENTS.md rule 6).
  enum ShowcaseDocuments {
    struct Document {
      /// What `-seed-library showcase-<key>` opens.
      let key: String
      let title: String
      let pages: [String]
    }

    static var current: [Document] {
      Locale.preferredLanguages.first?.hasPrefix("fr") == true ? french : english
    }

    static let english = [
      Document(
        key: "invoice", title: "Invoice INV-2026-0187",
        pages: [
          """
          Tax invoice

          Invoice number: INV-2026-0187
          Invoice date: 2 October 2026
          Due date: 1 November 2026
          Seller: Example Design Studio
          Buyer: Sample Garden Co.

          Brand identity, first stage: 1,800.00
          Website design, 12 pages: 2,400.00
          Photography, half a day: 450.00

          Subtotal: 4,650.00
          GST (10%): 465.00
          Total due: 5,115.00

          Payment terms: 30 days. All names are fictional.
          """
        ]),
      Document(
        key: "lease", title: "Residential lease",
        pages: [
          """
          Residential lease agreement

          Landlord: Example Property Holdings
          Tenant: Sample Tenant
          Premises: Unit 4, 12 Example Street

          1. Term. The lease starts on 1 November 2026 and runs for 12 months.
          2. Rent. The rent is 2,100.00 a month, paid in advance on the first day of each month.
          3. Bond. The tenant pays a bond of 4,200.00 before moving in.
          4. Repairs. The tenant reports any damage within 7 days. The landlord arranges urgent repairs \
          within 48 hours.
          5. Ending the lease. Either party may end the lease after the term with 28 days' written notice.
          """,
          """
          6. Pets. No pets without the landlord's written consent.
          7. Late payment. Rent more than 14 days late incurs a fee of 50.00.

          Signed by the landlord:

          Signed by the tenant:

          This agreement is synthetic sample content. All names are fictional.
          """,
        ]),
      Document(
        key: "report", title: "Quarterly report Q3 2026",
        pages: [
          """
          Quarterly report, Q3 2026
          Example Outdoor Co.

          Summary
          Revenue grew 12% on the previous quarter, to 1.84 million. Online orders made up 41% of sales, \
          up from 33%. Costs rose 5%, mainly from freight.

          Highlights
          - Two new stores opened, in the north and the west.
          - Customer returns fell from 6.1% to 4.8%.
          - The loyalty programme reached 18,000 members.
          """,
          """
          Revenue by channel

          Stores: 1.09 million (59%)
          Online: 0.75 million (41%)

          The online share rose in every month of the quarter. Weekend orders grew fastest.
          """,
          """
          Costs

          Freight costs rose 14% after a change of carrier. Staff costs were flat. Rent rose 3% with the \
          two new stores.
          """,
          """
          Outlook

          The next quarter covers the summer season. The team expects revenue between 2.0 and 2.2 million, \
          and plans one more store opening.

          This report is synthetic sample content. All names are fictional.
          """,
        ]),
    ]

    static let french = [
      Document(
        key: "invoice", title: "Facture FA-2026-0187",
        pages: [
          """
          Facture

          Numéro de facture : FA-2026-0187
          Date de facture : 2 octobre 2026
          Échéance : 1er novembre 2026
          Vendeur : Exemple Studio de design
          Client : Jardins Échantillon

          Identité visuelle, première étape : 1 800,00
          Conception du site web, 12 pages : 2 400,00
          Photographie, une demi-journée : 450,00

          Sous-total : 4 650,00
          TVA (20 %) : 930,00
          Total à payer : 5 580,00

          Conditions de paiement : 30 jours. Tous les noms sont fictifs.
          """
        ]),
      Document(
        key: "lease", title: "Contrat de location",
        pages: [
          """
          Contrat de location d'habitation

          Bailleur : Exemple Immobilier
          Locataire : Locataire Échantillon
          Logement : appartement 4, 12 rue de l'Exemple

          1. Durée. Le bail commence le 1er novembre 2026 pour une durée de 12 mois.
          2. Loyer. Le loyer est de 2 100,00 par mois, payable d'avance le premier jour de chaque mois.
          3. Dépôt de garantie. Le locataire verse un dépôt de 4 200,00 avant l'entrée dans les lieux.
          4. Réparations. Le locataire signale tout dommage sous 7 jours. Le bailleur fait faire les \
          réparations urgentes sous 48 heures.
          5. Fin du bail. Chaque partie peut mettre fin au bail à son terme avec un préavis écrit de 28 jours.
          """,
          """
          6. Animaux. Pas d'animaux sans l'accord écrit du bailleur.
          7. Retard de paiement. Un loyer payé avec plus de 14 jours de retard entraîne des frais de 50,00.

          Signature du bailleur :

          Signature du locataire :

          Ce contrat est un exemple de contenu fictif. Tous les noms sont fictifs.
          """,
        ]),
      Document(
        key: "report", title: "Rapport trimestriel T3 2026",
        pages: [
          """
          Rapport trimestriel, T3 2026
          Exemple Plein Air

          Synthèse
          Le chiffre d'affaires a progressé de 12 % sur le trimestre précédent, à 1,84 million. Les commandes \
          en ligne représentent 41 % des ventes, contre 33 %. Les coûts ont augmenté de 5 %, surtout le transport.

          Faits marquants
          - Deux nouveaux magasins ont ouvert, au nord et à l'ouest.
          - Les retours clients sont passés de 6,1 % à 4,8 %.
          - Le programme de fidélité compte 18 000 membres.
          """,
          """
          Chiffre d'affaires par canal

          Magasins : 1,09 million (59 %)
          En ligne : 0,75 million (41 %)

          La part en ligne a progressé chaque mois du trimestre. Les commandes du week-end ont le plus augmenté.
          """,
          """
          Coûts

          Les coûts de transport ont augmenté de 14 % après un changement de transporteur. Les coûts de \
          personnel sont stables. Les loyers ont augmenté de 3 % avec les deux nouveaux magasins.
          """,
          """
          Perspectives

          Le prochain trimestre couvre la saison d'été. L'équipe prévoit un chiffre d'affaires entre 2,0 et \
          2,2 millions, et l'ouverture d'un magasin de plus.

          Ce rapport est un exemple de contenu fictif. Tous les noms sont fictifs.
          """,
        ]),
    ]
  }
#endif
