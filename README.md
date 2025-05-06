# Mudhkir - Medication Tracking and Reminder Application

Mudhkir is a smart, user-friendly, and Arabic-localized medication management application designed to assist individuals—especially elderly and middle-aged users—in managing their medication routines. The app offers adaptive reminders, caregiver notifications, and a simplified interface to improve adherence and overall health outcomes.

## About the Project

Medication adherence is critical yet challenging for patients managing complex regimens. Mudhkir addresses these challenges by offering:

- Adaptive reminders that adjust based on user behavior.
- Caregiver integration for collaborative care.
- Arabic language support and elder-friendly UI.
- Cost-effective alternative to physical dispensers.
- Seamless real-time syncing and accessibility.

## Features

- **User-Centric Medication Tracking**: Easy-to-use schedule management with medication images.
- **Adaptive Reminder System**: Smart notifications that align with user routines and adjust if doses are missed.
- **Caregiver Support Tools**: Real-time alerts and shared access to user schedules.
- **Companion System**: Allows linking caregivers for collaborative management.
- **Secure Authentication and Data Privacy**: Managed by Firebase with encrypted user data.
- **Offline Access and Sync**: Users can manage medication even without internet, syncing when back online.
- **Simple and Accessible UI**: RTL support, large buttons, and clear navigation designed for elderly users.

## Technology Stack

| Technology | Purpose |
|------------|---------|
| Flutter | Frontend UI Development |
| Dart | Application Logic |
| Firebase Auth | User Authentication |
| Cloud Firestore | Real-time Database |
| ImgBB API | Image Uploading |
| Codemagic | CI/CD and iOS Testing |
| Figma | UI/UX Design |
| Git & GitHub | Version Control |

## System Overview

### Architecture
Mudhkir uses a modular design with a feature-first architecture for maintainability and scalability. Core components include:

- **Frontend (Flutter)**: User interface and notification handling.
- **Backend (Firebase & ImgBB)**: Authentication, data storage, and image handling.
- **Notifications**: Local notifications using scheduled triggers.
- **Companion System**: Linked user access for caregivers.
