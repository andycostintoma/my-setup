---
name: go-bff
description: "Activate when working on a Backend for Frontend (BFF) service — covers facade pattern, JWT auth, data transformation between frontend and internal APIs, stats aggregation, and dashboard-specific features."
license: MIT
---

# Go Backend for Frontend (BFF) Patterns

## Architecture

A BFF service acts as a facade between the frontend and internal microservices:

- **No business logic** — only orchestration and data transformation
- Single entry point for frontend to access multiple backend services
- Transforms requests/responses between frontend and internal formats
- Allows frontend and backend APIs to evolve independently
- Uses a **service registry** for all internal service connections

## Handler Pattern

```go
// ports/grpc/order_handler.go
func (h *OrderHandler) Get(ctx context.Context, req *pb.OrderGetRequest) (*pb.OrderGetReply, error) {
    claims := auth.ClaimsFromContext(ctx)

    // Convert frontend request → internal service request
    internalReq := &order_pb.OrderGetRequest{
        CompanyId: claims.CompanyID,
        OrderId:   req.GetOrderId(),
    }

    // Call internal microservice
    reply, err := h.clients.OrderService.Get(ctx, internalReq)
    if err != nil {
        return nil, err
    }

    // Convert internal response → frontend response
    return toFrontendOrderReply(reply), nil
}
```

## Authentication

```go
func (i *AuthInterceptor) authorize(ctx context.Context) (context.Context, error) {
    token := extractBearerToken(ctx)

    claims, err := i.jwt.VerifyClaims(token)
    if err != nil {
        return nil, status.Error(codes.Unauthenticated, "invalid token")
    }

    // Extract tenant context from metadata
    md, _ := metadata.FromIncomingContext(ctx)
    companyID := md.Get("company_id")[0]

    ctx = auth.SetUserID(ctx, claims.UserID)
    ctx = auth.SetCompanyID(ctx, companyID)

    return ctx, nil
}
```

## Data Transformation

Keep converters in a dedicated file or package within the ports layer:

```go
// ports/grpc/converters.go
func toFrontendOrderReply(internal *order_pb.OrderGetReply) *pb.OrderGetReply {
    return &pb.OrderGetReply{
        Id:            internal.GetId(),
        Status:        internal.GetStatus(),
        DisplayStatus: humanizeStatus(internal.GetStatus()),
        FormattedDate: formatDate(internal.GetCreatedAt()),
        // UI-specific computed fields
        CanEdit:     canEdit(internal),
        ShowAlerts:  hasActiveAlerts(internal),
        StatusColor: statusColor(internal.GetStatus()),
    }
}
```

## Proto Structure

Use hierarchical model naming for different view contexts:

```protobuf
// Frontend-facing proto
message OrderGetRequest {
    string order_id = 1;
}

message OrderGetReply {
    string id = 1;
    string status = 2;
    string display_status = 3;    // UI-friendly
    string formatted_date = 4;    // Pre-formatted for display
    bool can_edit = 5;            // Permission computed server-side
}

// List with pagination
message OrderListRequest {
    int64 page = 1;
    int64 per_page = 2;
    repeated ColumnFilter column_filters = 3;
    string search_query = 4;
    SortField sort_by = 5;
    SortDirection sort_direction = 6;
}

message OrderListReply {
    repeated OrderListItem items = 1;
    int64 total_count = 2;
}
```

## Stats Aggregation

```go
func (h *StatsHandler) GetDashboardStats(ctx context.Context, req *pb.StatsRequest) (*pb.StatsReply, error) {
    claims := auth.ClaimsFromContext(ctx)

    // Parallel fetch from multiple internal services
    eg, childCtx := errgroup.WithContext(ctx)

    var orderStats *order_pb.StatsReply
    eg.Go(func() error {
        var err error
        orderStats, err = h.clients.OrderService.GetStats(childCtx, &order_pb.StatsRequest{
            CompanyId: claims.CompanyID,
            DateRange: toInternalDateRange(req.GetDateRange()),
        })
        return err
    })

    var shippingStats *shipping_pb.StatsReply
    eg.Go(func() error {
        var err error
        shippingStats, err = h.clients.ShippingService.GetStats(childCtx, &shipping_pb.StatsRequest{
            CompanyId: claims.CompanyID,
            DateRange: toInternalDateRange(req.GetDateRange()),
        })
        return err
    })

    if err := eg.Wait(); err != nil {
        return nil, err
    }

    return &pb.StatsReply{
        TotalOrders:    orderStats.GetTotal(),
        TotalShipments: shippingStats.GetTotal(),
        Combined:       calculateCombined(orderStats, shippingStats),
    }, nil
}
```

## Bulk Operations

```go
func (h *OrderHandler) BulkStatusUpdate(ctx context.Context, req *pb.BulkUpdateRequest) (*pb.BulkUpdateReply, error) {
    results := make([]*pb.UpdateResult, 0, len(req.GetIds()))

    for _, id := range req.GetIds() {
        _, err := h.clients.OrderService.UpdateStatus(ctx, &order_pb.StatusUpdateRequest{
            OrderId:   id,
            NewStatus: req.GetNewStatus(),
        })
        results = append(results, &pb.UpdateResult{
            Id:    id,
            Error: errorMessage(err),
        })
    }

    return &pb.BulkUpdateReply{
        Results:      results,
        SuccessCount: countSuccesses(results),
        FailureCount: countFailures(results),
    }, nil
}
```

## Best Practices

- **Never implement business logic** — delegate everything to internal services
- Validate and sanitize all frontend input
- Use `errgroup` for parallel calls to independent internal services
- Handle partial failures gracefully (some services may fail while others succeed)
- Cache aggregated data when appropriate
- Provide user-friendly error messages — never expose internal service details
- Use field masks to fetch only required data from internal services
- Use a service registry for all internal service connections — never hardcode addresses
