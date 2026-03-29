import 'package:flutter/material.dart';

import 'candidate_list_card.dart';

class CandidateCardSmall extends StatelessWidget {
  const CandidateCardSmall({
    super.key,
    required this.onTap,
    required this.name,
    this.ageText = '',
    required this.profession,
    required this.location,
    this.category = '',
    this.language = '',
    this.experience = '',
    this.topRight,
    this.statusBadge,
    this.footer,
    this.onContactTap,
    this.readyToWork = false,
    this.hasWorkDocuments = false,
    this.profileViews = 0,
    this.isNewCandidate = false,
    this.hasDriverLicense = false,
    this.hasCar = false,
    this.readyToRelocate = false,
    this.contactsOpened = false,
    this.hasOfferSent = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final VoidCallback? onTap;
  final String name;
  final String ageText;
  final String profession;
  final String location;
  final String category;
  final String language;
  final String experience;
  final Widget? topRight;
  final Widget? statusBadge;
  final Widget? footer;
  final VoidCallback? onContactTap;
  final bool readyToWork;
  final bool hasWorkDocuments;
  final int profileViews;
  final bool isNewCandidate;
  final bool hasDriverLicense;
  final bool hasCar;
  final bool readyToRelocate;
  final bool contactsOpened;
  final bool hasOfferSent;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return CandidateListCard(
      onTap: onTap,
      name: name,
      ageText: ageText,
      profession: profession,
      location: location,
      category: category,
      language: language,
      experience: experience,
      topRight: topRight,
      statusBadge: statusBadge,
      footer: footer,
      onContactTap: onContactTap,
      readyToWork: readyToWork,
      hasWorkDocuments: hasWorkDocuments,
      profileViews: profileViews,
      isNewCandidate: isNewCandidate,
      hasDriverLicense: hasDriverLicense,
      hasCar: hasCar,
      readyToRelocate: readyToRelocate,
      contactsOpened: contactsOpened,
      hasOfferSent: hasOfferSent,
      margin: margin,
    );
  }
}
