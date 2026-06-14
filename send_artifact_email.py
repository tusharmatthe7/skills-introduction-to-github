#!/usr/bin/env python3
import argparse
import os
import smtplib
import ssl
from email.message import EmailMessage
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Send an artifact file by email using SMTP."
    )
    parser.add_argument("--smtp-server", default=os.getenv("SMTP_SERVER", "smtp.gmail.com"))
    parser.add_argument("--smtp-port", type=int, default=int(os.getenv("SMTP_PORT", 587)))
    parser.add_argument("--smtp-user", default=os.getenv("SMTP_USER"))
    parser.add_argument("--smtp-password", default=os.getenv("SMTP_PASSWORD"))
    parser.add_argument("--from-email", default=os.getenv("FROM_EMAIL"))
    parser.add_argument("--to-email", default=os.getenv("TO_EMAIL"))
    parser.add_argument("--subject", default="Oracle artifact bundle")
    parser.add_argument("--body", default="Please find the attached Oracle artifact bundle.")
    parser.add_argument("--attachment", dest="attachment", help="Path to the artifact file to attach")
    parser.add_argument("attachment", nargs="?", help="Path to the artifact file to attach")
    return parser.parse_args()


def main():
    args = parse_args()

    if not args.smtp_user:
        raise SystemExit("ERROR: SMTP user must be provided via --smtp-user or SMTP_USER environment variable.")
    if not args.smtp_password:
        raise SystemExit("ERROR: SMTP password must be provided via --smtp-password or SMTP_PASSWORD environment variable.")
    if not args.from_email:
        raise SystemExit("ERROR: From email must be provided via --from-email or FROM_EMAIL environment variable.")
    if not args.to_email:
        raise SystemExit("ERROR: To email must be provided via --to-email or TO_EMAIL environment variable.")

    attachment_path = Path(args.attachment)
    if not attachment_path.exists():
        raise SystemExit(f"ERROR: Attachment path does not exist: {attachment_path}")

    message = EmailMessage()
    message["Subject"] = args.subject
    message["From"] = args.from_email
    message["To"] = args.to_email
    message.set_content(args.body)

    with attachment_path.open("rb") as fh:
        data = fh.read()
        maintype = "application"
        subtype = "octet-stream"
        if attachment_path.suffix == ".gz":
            subtype = "gzip"
        message.add_attachment(
            data,
            maintype=maintype,
            subtype=subtype,
            filename=attachment_path.name,
        )

    context = ssl.create_default_context()
    with smtplib.SMTP(args.smtp_server, args.smtp_port, timeout=60) as server:
        server.starttls(context=context)
        server.login(args.smtp_user, args.smtp_password)
        server.send_message(message)

    print(f"Email sent to {args.to_email} with attachment {attachment_path.name}.")


if __name__ == "__main__":
    main()
