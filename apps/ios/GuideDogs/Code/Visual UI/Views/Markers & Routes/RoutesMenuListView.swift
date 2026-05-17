//
//  RoutesMenuListView.swift
//  Soundscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import SwiftUI

struct RoutesMenuListView: View {
    @EnvironmentObject var navHelper: MarkersAndRoutesListNavigationHelper

    @State private var sort: SortStyle

    init() {
        _sort = State(initialValue: SettingsContext.shared.defaultMarkerSortStyle)
    }

    var body: some View {
        ZStack {
            Color.quaternaryBackground
                .ignoresSafeArea()

            ScrollView {
                RoutesList(sort: $sort)
            }
            .padding([.top], 1)
        }
        .navigationTitle(GDLocalizedTextView("routes.title"))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink(destination: RouteCreateFlowView().environmentObject(navHelper as ViewNavigationHelper)) {
                    Image(systemName: "plus")
                        .font(.system(size: 22))
                        .foregroundColor(.primaryForeground)
                        .padding([.all], 4)
                        .accessibilityLabel(GDLocalizedTextView("route_detail.action.create"))
                        .accessibilityHint(GDLocalizedTextView("route_detail.action.create.hint"))
                }
                .accessibilityElement(children: .combine)
                .embedToolbarContent()
            }
        }
    }
}
