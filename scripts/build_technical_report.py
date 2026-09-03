from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Image,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "technical-report.pdf"
ARCH = ROOT / "docs" / "architecture-overview.webp"
FONT_PATH = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
FONT = "DejaVuSans"


def build_styles():
    pdfmetrics.registerFont(TTFont(FONT, str(FONT_PATH)))
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="ReportTitle",
            fontName=FONT,
            fontSize=18,
            leading=21,
            alignment=TA_CENTER,
            spaceAfter=5,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ReportHeading",
            fontName=FONT,
            fontSize=11.2,
            leading=13.5,
            textColor=colors.HexColor("#153B73"),
            spaceBefore=5,
            spaceAfter=3,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ReportBody",
            fontName=FONT,
            fontSize=9.0,
            leading=11.4,
            spaceAfter=3,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ReportSmall",
            fontName=FONT,
            fontSize=8.0,
            leading=9.5,
            textColor=colors.HexColor("#444444"),
        )
    )
    styles.add(
        ParagraphStyle(
            name="ReportCell",
            fontName=FONT,
            fontSize=8.3,
            leading=10.0,
        )
    )
    styles.add(
        ParagraphStyle(
            name="ReportCellHead",
            fontName=FONT,
            fontSize=8.5,
            leading=10.0,
            textColor=colors.HexColor("#153B73"),
        )
    )
    return styles


def table_style(header_first_col=False):
    commands = [
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#D5DDEB")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]
    if header_first_col:
        commands.append(("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#EAF1FB")))
    else:
        commands.append(("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EAF1FB")))
    return TableStyle(commands)


def add_page_number(canvas, doc):
    canvas.setFont(FONT, 8)
    canvas.setFillColor(colors.HexColor("#666666"))
    canvas.drawRightString(A4[0] - 15 * mm, 10 * mm, f"Page {doc.page}")


def build_report():
    styles = build_styles()
    story = []

    story.append(Paragraph("PaperAgent: OPEA-based Cloud-Edge Academic Intelligence", styles["ReportTitle"]))
    story.append(Paragraph("Competition Technical Report (2 pages)", styles["ReportSmall"]))
    story.append(Spacer(1, 3 * mm))

    overview = [
        [
            Paragraph("<b>Problem</b>", styles["ReportCellHead"]),
            Paragraph(
                "Academic writing increasingly relies on generative AI, but a cloud-only workflow may expose sensitive drafts and research materials, while a local-only workflow lacks scalable literature retrieval and service orchestration.",
                styles["ReportCell"],
            ),
        ],
        [
            Paragraph("<b>Solution</b>", styles["ReportCellHead"]),
            Paragraph(
                "PaperAgent separates tasks according to privacy and compute characteristics: writing assistance runs locally on an AI PC, while literature retrieval and grounded QA are composed as modular OPEA services in the cloud.",
                styles["ReportCell"],
            ),
        ],
        [
            Paragraph("<b>AI for Good value</b>", styles["ReportCellHead"]),
            Paragraph(
                "The system reduces privacy risk, lowers the barrier for academic assistance, and provides a reproducible open-source path for universities, researchers, and enterprise knowledge workers.",
                styles["ReportCell"],
            ),
        ],
    ]
    overview_table = Table(overview, colWidths=[28 * mm, 148 * mm])
    overview_table.setStyle(table_style(header_first_col=True))
    story.extend([overview_table, Spacer(1, 3 * mm)])

    story.append(Paragraph("System Architecture", styles["ReportHeading"]))
    story.append(
        Paragraph(
            "PaperAgent uses a coordinated cloud-edge layout. Privacy-sensitive grammar checking, academic polishing, and translation are executed locally through Qwen3-8B INT4 and HY-MT1.5-1.8B. Literature retrieval and grounded academic QA are implemented as OPEA MicroServices and composed by a MegaService.",
            styles["ReportBody"],
        )
    )

    with PILImage.open(ARCH) as source:
        width, height = source.size
    scale = min((176 * mm) / width, (142 * mm) / height)
    story.append(Image(str(ARCH), width=width * scale, height=height * scale))
    story.append(Spacer(1, 1 * mm))
    story.append(
        Paragraph(
            "Figure 1. PaperAgent cloud-edge architecture with edge AI services, OPEA cloud services, data layer, and end-to-end data flows.",
            styles["ReportSmall"],
        )
    )

    story.append(PageBreak())
    story.append(Paragraph("Technical Implementation and Reproducibility", styles["ReportTitle"]))

    story.append(Paragraph("1. OPEA-based service composition", styles["ReportHeading"]))
    story.append(
        Paragraph(
            "PaperAgent implements actual OPEA service composition rather than calling a single external API from a monolithic application. The cloud path includes a Retriever MicroService, a Prompt MicroService, an official OPEA LLM TextGen service, and a MegaService that exposes a unified endpoint. The effective runtime chain is: <b>paperagent-retriever -&gt; paperagent-prompt -&gt; opea-service@llm -&gt; PaperAgent MegaService</b>.",
            styles["ReportBody"],
        )
    )

    story.append(Paragraph("2. Edge inference", styles["ReportHeading"]))
    story.append(
        Paragraph(
            "The edge layer is not a mock interface. Qwen3-8B INT4 OpenVINO runs on Intel NPU for grammar checking and academic polishing. HY-MT1.5-1.8B is prepared in an OpenVINO-compatible INT4 path and runs locally for academic translation. This task placement keeps privacy-sensitive text processing on the AI PC.",
            styles["ReportBody"],
        )
    )

    story.append(Paragraph("3. Deployment workflow", styles["ReportHeading"]))
    deployment_points = [
        "A single Windows entry point (<b>deploy.bat</b>) prepares the runtime environment, installs required dependencies, downloads models, and starts cloud and edge services.",
        "Model weights are not committed to the repository. The deployment flow downloads required runtime models automatically. ModelScope is the default source; Hugging Face is retained as a fallback.",
        "The public repository includes only sanitized synthetic demo data, safe configuration templates, health checks, and sensitive-source scanning scripts.",
    ]
    for point in deployment_points:
        story.append(Paragraph("&bull; " + point, styles["ReportBody"]))

    story.append(Paragraph("4. Evaluation focus", styles["ReportHeading"]))
    evaluation = [
        [Paragraph("<b>Dimension</b>", styles["ReportCellHead"]), Paragraph("<b>What reviewers can verify</b>", styles["ReportCellHead"])],
        [Paragraph("Functional integration", styles["ReportCell"]), Paragraph("One-click deployment, model preparation, service startup, and unified UI entry.", styles["ReportCell"])],
        [Paragraph("Local AI capability", styles["ReportCell"]), Paragraph("Grammar check / academic polish on local Qwen3 and translation on local HY-MT.", styles["ReportCell"])],
        [Paragraph("OPEA usage", styles["ReportCell"]), Paragraph("Actual retriever, prompt, LLM, and MegaService composition; topology endpoint can be inspected.", styles["ReportCell"])],
        [Paragraph("Privacy-aware design", styles["ReportCell"]), Paragraph("Sensitive writing assistance remains on the AI PC while literature retrieval and orchestration run in the cloud.", styles["ReportCell"])],
        [Paragraph("Open-source reproducibility", styles["ReportCell"]), Paragraph("Apache-2.0 source code, deployment scripts, safe demo data, technical report, architecture figure, and CI validation.", styles["ReportCell"])],
    ]
    evaluation_table = Table(evaluation, colWidths=[42 * mm, 134 * mm])
    evaluation_table.setStyle(table_style())
    story.extend([evaluation_table, Spacer(1, 2 * mm)])

    story.append(Paragraph("5. Dependency note", styles["ReportHeading"]))
    story.append(
        Paragraph(
            "The competition edition uses <b>pypdf</b> for local PDF page counting and fallback text extraction. MinerU remains available as the optional higher-fidelity parser when a runtime token is supplied. This keeps the fallback parser lightweight while avoiding redistribution concerns associated with the previous PDF dependency.",
            styles["ReportBody"],
        )
    )

    story.append(Paragraph("Conclusion", styles["ReportHeading"]))
    story.append(
        Paragraph(
            "PaperAgent demonstrates a practical cloud-edge academic assistant: local AI inference is used where privacy matters, while OPEA services provide modular literature retrieval and grounded answer generation. The project is packaged as a reproducible, open-source competition submission with deployment automation and verifiable runtime components.",
            styles["ReportBody"],
        )
    )

    document = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        leftMargin=15 * mm,
        rightMargin=15 * mm,
        topMargin=12 * mm,
        bottomMargin=12 * mm,
    )
    document.build(story, onFirstPage=add_page_number, onLaterPages=add_page_number)


if __name__ == "__main__":
    build_report()
    print(f"Generated: {OUTPUT}")
